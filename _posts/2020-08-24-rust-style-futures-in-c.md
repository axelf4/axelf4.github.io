---
layout: post
title: "Rust-style futures in C"
date: 2020-08-24
description: "Implementing Rust-style futures in C"
---

All networking applications essentially boil down to stringing together
multiple asynchronous calls in the *right* way.
Traditionally for programs written in C, this would be done by
registering callbacks where the callee either handles the event itself
or dispatches through a state machine.
In such implementations, however, reasoning about memory safety
can be treacherous, with it sometimes requiring full-program knowledge.
Futures, or promises, as they are also referred to,
ease in that regard by allowing asynchronous programs
to be written in direct style, keeping the control flow linear.

All things considered, I do think that futures can be a good fit
for C programming under the right circumstances.
I also hope this article can serve to help one understand Rust futures,
by being a separate reference that only touches the fundamentals.

The Rust futures story is especially interesting because it is
fundamentally different from the usual workings of futures
in functional languages or, say, JavaScript.
Whereas other implementations are *push*-based -
meaning you give a function to be pushed to with
the resolved result of the future -
Rust futures are *poll*-based.
Let us see how this looks in C with the simplification
that we limit ourselves to a single task,
i.e. one top-level future running on one thread.
This is common in embedded programming, and still *fairly* manageable
without the security guarantees given by Rust.
[libuv] is used for the event loop.
No heap allocations will be required - it is all downhill from here
(Get it? Because the stack grows down.) -
other than those imposed by the libuv interface.

The main [`std::future::Future`][rs-Future] trait
translated into C as a virtual method table becomes
```c
enum Poll { POLL_PENDING, POLL_READY };

struct Future {
	enum Poll (*poll)(struct Future *self, struct Context *ctx);

	// For now let's skip this method
	// void (*drop)(struct Future *self, struct Context *ctx);
};
```
As an example, let us consider the simplest case:
A future that immediately resolves with the number `4`,
```c
enum Poll simpleFuturePoll(struct Future *self, struct Context *ctx) {
	struct SimpleFuture *state = (struct SimpleFuture *) self;
	self->result = 4;
	return POLL_READY;
}

struct SimpleFuture {
	struct Future future;
	int result;
} simpleFuture = { .future = { .poll = simpleFuturePoll, } };

// ... and in the event loop
simpleFuture.poll(&simpleFuture, ctx); // => POLL_READY
// Here we can now use the result
simpleFuture.result // => 4
```
To *attempt* to resolve the future, we poll it;
it returns `POLL_READY` and as such we are done.
And for futures that instead return `POLL_PENDING` when polled,
we just make sure to poll them again later -
futures are lazy and do not make progress unless actively told to do so.
No one knows better than the future itself when it should
be polled again - *awoken* -
so the context given to all futures allows them to awaken their own task.
With many parallel tasks the additional complexity would make itself apparent here,
but in our case something like
```c
struct Context {
	struct Future *mainFuture;
	uv_loop_t loop;
};

void wakeTask(struct Context *ctx) {
	if (ctx->mainFuture->poll(ctx->mainFuture, ctx) == POLL_READY) {
		exit(EXIT_SUCCESS); // Finished!
	}
}
```
will suffice.
Polling the future once at startup will then kick off the machinery.

For a libuv timer future, we would want to write something like
```c
enum TimerStatus { TIMER_NOT_STARTED, TIMER_WAITING, TIMER_FINISHED };

struct TimerFuture {
	struct Future future;
	enum TimerStatus status;
	union {
		uint64_t timeout;
		uv_timer_t *handle;
	};
};

static void uvCloseFree(uv_handle_t *handle) {
	free(handle);
}

static void timerCb(uv_timer_t *handle) {
	struct TimerFuture *state = handle->data;
	struct Context *ctx = handle->loop.data;
	uv_close((uv_handle_t *) handle, uvCloseFree);
	state->status = TIMER_FINISHED;
	wakeTask(ctx);
}

static enum Poll timerFuturePoll(struct Future *self, struct Context *ctx) {
	struct TimerFuture *state = (struct TimerFuture *) self;
	switch (state->status) {
		case TIMER_NOT_STARTED:
			uint64_t timeout = state->timeout;
			state->handle = malloc(sizeof *state->handle);
			uv_timer_init(ctx.loop, &state->handle);
			state->handle->data = state;
			uv_timer_start(&state->handle, timerCb, timeout, /* no repeat */ 0);
			state->status = TIMER_WAITING;
			/* fallthrough */
		case TIMER_WAITING:
			return POLL_PENDING;
		case TIMER_FINISHED:
			return POLL_READY;
	}
	return POLL_READY;
}

struct TimerFuture timerFutureNew(uint64_t timeout) {
	return (struct TimerFuture) {
		.future = { .poll = timerFuturePoll, },
		.status = TIMER_NOT_STARTED,
		.timeout = timeout,
	};
}
```
The timer handle is made to hold a reference to the future in
its user data field,
so that the callback knows which future to toggle the status on.
However this requires the future object to be pinned in memory,
moving it would leave the reference dangling.
Rust deals with this unsafety using the [Pin construct][rs-pin],
that wraps a pointer type, `P`,
and only permits operations that cannot move the pointee
(for cases where it may not always be safe to do so, i.e. `P: !Unpin`)
and ensures its memory remains valid until it gets dropped,
or helps make manually vetted code *nonleaky*.
In C there is no such thing;
the closest you will get is with a red paragraph buried in the documentation.
This means treading with care,
allocating storage for the main future once and never copying it, and
only referring to futures with pointers to their static place in memory.

Note that it is possible to get by with just one global `uv_timer_t`
by recognizing that whenever the main future is awoken either:
(I) A timer fired, necessarily the one with the shortest timeout; or
(II) All timers need to be dropped and reset, since the futures form a tree,
as we will see.

## After you

Running multiple futures sequentially is just a matter of
constructing a new future that polls each future to completion,
one after the other.
The poll method of the outer future will have to return `POLL_PENDING`
after each intermediate step,
before continuing where it left off - like a coroutine.
Rust turns each future into a state machine,
and doing the same in C means playing the part of the Rust compiler.
An adaptation of [Duff's device][duffs-device],
as [described by Simon Tatham][Coroutines-in-C],
can help cut down on the boilerplate.
The idea is that with a `switch` statement enveloping the whole function body,
you can yield by creating a unique label using the `__LINE__` macro
where execution will begin upon reentry,
setting the switch expression as such, and returning.
The following macros do just that
```c
typedef unsigned Coroutine;

#define COR_START(s) switch (*(s)) { case 0:;
#define COR_YIELD(s, r) do {*(s) = __LINE__; return (r); case __LINE__:;} while(0)
#define COR_END }
```
where `s` is a pointer to the coroutine state.
Great care has to be taken because when returning all locals are invalidated -
if only there was a language that could statically check for such mistakes.
Awaiting then becomes
```c
#define AWAIT(s, ctx, fut) while ((fut)->poll((fut), (ctx)) == POLL_PENDING) \
	COR_YIELD((s), POLL_PENDING)
```
that is, yielding until the given future is resolved.

To illustrate, here is a future that prints four times to standard output,
first thrice at one-second intervals, and then again after two more seconds:
```c
struct TestFuture {
	struct Future future;
	Coroutine c;
	union {
		struct {
			int i;
			struct TimerFuture timerA;
		};
		struct TimerFuture timerB;
	};
};

struct TestFuture testFutureNew() {
	return (struct TestFuture) {
		.future = { .poll = testFuturePoll, },
		.c = 0,
	};
}
```

<div style="overflow-x: scroll;"><table>
<thead><tr><th>With macros</th><th>Desugared</th></tr></thead>
<tr>
<td markdown="block">
```c
enum Poll testFuturePoll(struct Future *self, struct Context *ctx) {
	struct TestFuture *state = (struct TestFuture *) self;
	COR_START(&state->c)

	for (state->i = 0; state->i < 3; ++state->i) {
		state->timerA = timerFutureNew(1000);
		AWAIT(&state->c, ctx, &state->timerA.future);
		printf("One second has passed!");
	}

	state->timerB = timerFutureNew(2000);
	AWAIT(&state->c, ctx, &state->timerB.future);
	printf("Another two seconds have passed!");

	COR_END
	return POLL_READY;
}
```
</td>
<td markdown="block">
```c
enum Poll testFuturePoll(struct Future *self, struct Context *ctx) {
	struct TestFuture *state = (struct TestFuture *) self;
	switch (state->c) {
		case 0: ;
		for (state->i = 0; state->i < 3; ++state->i) {
			state->timerA = timerFutureNew(1000);
			while (state->timerA.future.poll(&state->timerA.future, ctx) == POLL_PENDING) {
				state->c = 1;
				return POLL_PENDING;
				case 1: ;
			}
			printf("One second has passed!");
		}

		state->timerB = timerFutureNew(2000);
		while (state->timerB.future.poll(&state->timerB.future, ctx) == POLL_PENDING) {
			state->c = 2;
			return POLL_PENDING;
			case 2: ;
		}
		printf("Another two seconds have passed!");
	}
	return POLL_READY;
}
```
</td>
</tr>
</table></div>
Note that the local `i` had to be spilled to the future struct
to persist across yield points,
and that unions are used to show what variables are active at each step,
and squeeze out that last driblet of performance even in the face of
uncompromising undefined behavior threats from all directions.

## Off to the races

In a similar vein, multiple futures can be made to run in parallel
using a future combinator whose poll method polls all of its children
and either waits for all to complete - *joins* them,
or selects the first to become ready.
The latter is a tad more difficult, so let us focus on that.
The reason is that after the first future has been resolved,
the rest may still be running, their memory possibly referenced elsewhere.
This is where the `drop()` method that we have skimmed over comes in.
Dropping a pinned object should relax the constraint
that its memory remains valid.
The drop implementation of `TimerFuture` above could for example
call `uv_timer_stop()` so the callback never fires
or overwrite the dangling reference to the future with `NULL`.
For other types, since their drop implementations are not auto-generated,
like would happen in Rust, it can be useful to define
`futureDropNoop()` and `futureDropUnimplemented()` -
that does nothing, and aborts, respectively - to use where appropriate.

The following implementation optimizes for the case where you want to
have a heterogeneous statically-sized list of futures race,
by allowing that list to be statically allocated in some object,
only requiring their offsets from `offsetof()` to be given:
```c
struct Race {
	struct Future future;
	bool finished;
	union {
		struct {
			struct Future *base; ///< Base pointer.
			size_t count; ///< Number of futures in the race.
			size_t *offsets; ///< Offsets from base to memory of each future.
		};
		size_t victor; ///< Index of the future that won the race.
	};
};

#define RACE_GET_NTH(state, n) ((struct Future *) ((char *) (state)->base + (state)->offsets[n]))

enum Poll futureRacePoll(struct Future *self, struct Context *ctx) {
	struct Race *state = (struct Race *) self;
	for (size_t i = 0; i < state->numFutures; ++i) {
		struct Future *future = RACE_GET_NTH(state, i);
		if (future->poll(future, ctx) == POLL_READY) {
			// Drop all other futures
			for (size_t j = 0; j < state->numFutures; ++j) {
				if (i == j) continue;
				struct Future *future = RACE_GET_NTH(state, j);
				future->drop(future, ctx);
			}

			// Set result of race
			state->finished = true;
			state->victor = i;
			return POLL_READY;
		}
	}
	return POLL_PENDING;
}
```

One thing to keep in mind is that if your main future consists of
a race in a loop, say between a ten-microsecond timer and a future
that always opens a new socket the first time it is polled,
then the socket will be torn down and reopened on every loop iteration.
To remedy this, either rethink if a single task is the right tool,
or maybe have the socket be opened once on program startup instead -
dropping or enqueuing received data while the future is not awaited.

## Conclusion

The coroutines for implementing the future state machine we have described
are *stackless*, as opposed to *stackful*:
When a future is constructed exactly enough storage is allocated
to hold all data that is alive at any one point,
instead of a generically sized, growable stack-frame.
This has the limitation that futures cannot be recursive
(unbounded size!) without indirection,
but comes with the additional advantage that they are
completely transparent to the optimizer, even without special support.
Since Rust futures do not use vtables,
`rustc` is able to inline to the full extent of its desires;
awaiting a constant future will be completely optimized away
(which is cool, at the least).

For completeness, some of the ways in which what has been described
differs from how things are done in Rust are that
in the Rust ecosystem, different parts of the event loop have been abstracted
to allow one to pick and match:
* The **Executor** is responsible for scheduling tasks on a set of threads.

  It will pass a custom [**Waker**][rs-Waker] in a [**Context**][rs-Context]
  to each future.
  If the future is concerned with I/O it then hands the waker to:
* The **Reactor** which listens on events from the operating system using
  [epoll], [IOCP], etc.

Also, a lot of calls to `drop()` that the Rust compiler would insert that
would turn into no-ops (e.g. those on resolved futures) have been omitted.

Thank you for reading!
Needless to say,
this all raises the question of why one would not just use Rust,
but as someone considering this I am sure you have a crystal clear answer ;).
Why stop at the halfway mark though?
The logical next step after getting your feet wet is to add a full effects system,
as described in [this technical report][algeff-in-c-tr].
Till that becomes commonplace, however, I will look Back to the Future as a useful pattern.

[rs-Context]: https://doc.rust-lang.org/std/task/struct.Context.html
[rs-Future]: https://doc.rust-lang.org/std/future/trait.Future.html
[rs-Waker]: https://doc.rust-lang.org/std/task/struct.Context.html
[rs-pin]: https://doc.rust-lang.org/std/pin/index.html
[libuv]: https://libuv.org/
[Coroutines-in-C]: https://www.chiark.greenend.org.uk/~sgtatham/coroutines.html
[duffs-device]: https://en.wikipedia.org/wiki/Duff%27s_device
[epoll]: https://man7.org/linux/man-pages/man7/epoll.7.html
[IOCP]: https://docs.microsoft.com/windows/win32/fileio/i-o-completion-ports
[algeff-in-c-tr]: https://www.microsoft.com/en-us/research/wp-content/uploads/2017/06/algeff-in-c-tr.pdf
