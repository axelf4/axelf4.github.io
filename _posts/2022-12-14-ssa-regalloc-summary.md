---
layout: post
title: Summary of "Register Allocation for programs in SSA-form"
date: 2022-12-14
---

> This summary of "Register Allocation for programs in SSA-form" by Hack, Grund, and Goos[^hack06]
> is adapted from my submission to the writing assignment
> in the course DAT315 The computer scientist in society at Chalmers University of Technology.
> The target audience is computer science students not necessarily having taken a compilers course.

Static single assignment (SSA) form as an intermediate representation
that compilers transform input source code into
has proven useful for facilitating optimization passes.
However, afterward the SSA property is destroyed
before the final code generation phases where e.g. machine code is emitted.
This paper shows there is merit in keeping the SSA form around
for the register allocation phase of codegen.

State-of-the-art imperative language compilers use *intermediate representations*
based on control-flow graphs which are turned into SSA form,
see figure 1.
Each node is a straight-line sequence of simple instructions called a *basic block*
where jumps to and from only happen at the start and end of the block respectively.
The SSA property further requires that each variable definition is assigned to only once.
This essentially gives immutability,
and so for example the dead-code elimination optimization on code in SSA form
is just a mark-and-sweep algorithm.

<figure>
<img src="{{site.url}}/assets/ssa-regalloc-summary/cfg-ssa.svg" alt="Example CFG converted into SSA" style="display: block; margin: auto;" />
<figcaption>
Figure 1: Control-flow graph for a program computing 10! (on the left)
and that CFG converted into SSA form (on the right),
by incrementing the variable <em>generation</em> (indicated by subscripts)
on each assignment
and adding parameters to each basic block.
</figcaption>
</figure>

Looking at the example program in figure 1,
we see that the non-SSA version uses two variables while the SSA version has more;
both IR:s allow for an unbounded amount of variables.
However, most physical computer architectures we may want to compile for
only have a limited set of fast registers.
To keep around values of variables beyond that,
they will have to be juggled in and out of the slower program stack memory.
Allocating these registers for each variable is done
in the phase called *register allocation*.

For register allocation it is natural to think about the *interference graph* of the program.
This is a graph where the nodes are the variables,
and two nodes share an edge if they are simultaneously *live*,
meaning at some point in the program both variables have been defined earlier,
and both will be used as inputs for later instructions.
The interference graph for the earlier example program is shown in figure 2.
The variables that interfere are those that cannot share the same register;
writing one could overwrite the other that later at its use-site would be read as garbage.
This means that allocating registers is solved by coloring the graph,
i.e. assigning colors to each node
such that no two neighboring nodes get the same color.
Each color will then correspond to a unique register.

<figure>
<img src="{{site.url}}/assets/ssa-regalloc-summary/interference-graph.svg" alt="Interference graph for earlier example program" style="display: block; margin: auto;" />
<figcaption>
Figure 2:
The interference graph for the SSA form program in figure 1.
It is 2-colorable.
</figcaption>
</figure>

The graph coloring approach for register allocation leads to the following algorithm,
proposed by Briggs, Cooper, and Torczon[^briggs94]
and shown in figure 3.
First we build the interference graph and try to color it.
If that fails, because too many registers were needed,
we split or remove some live range
by spilling a variable to the stack, essentially delegating it to slower memory,
before retrying.
Now building the full interference graph is time costly.
Furthermore we want to choose variables to spill
that are not used for a long time nor often, etc.
and these criteria makes the problem of optimal spilling NP-complete.
This all makes graph coloring register allocation complicated.

<figure>
<img src="{{site.url}}/assets/ssa-regalloc-summary/graph-color-regalloc.svg" alt="Graph-coloring register allocation" style="display: block; margin: auto;" />
<figcaption>
Figure 3:
Graph-coloring register allocation as proposed by Briggs, Cooper, and Torczon.
</figcaption>
</figure>

The idea of this paper is to use the fact that
interference graphs of SSA form programs turn out to be *triangulated*,
see figure 4,
in order to simplify register allocation.
It being simpler means more of a compiler's complexity budget
can be spent on things that improve the performance of generated code,
such as spilling more optimally.
This follows the work of Pereira and Palsberg[^pereira05] that showed
that 95% of interference graphs for the Java standard library
(compiled with the [JoeQ] compiler) were triangulated,
and gave a register allocation algorithm for that case.
For programs in SSA form where the graphs are always triangulated
one can go further.

<figure>
<img src="{{site.url}}/assets/ssa-regalloc-summary/chordal-graph.svg" alt="Example chordal graph" style="display: block; margin: auto;" />
<figcaption>
Figure 4:
Example of a triangulated graph.
For every cycle more than three nodes long there has to exist an edge -
shown in blue here - not part of that cycle.
</figcaption>
</figure>

Triangulated graphs have some useful properties:
(I) The *chromatic number* of a triangulated graph,
i.e. the smallest number of colors needed to color the graph,
equals the size of the largest *clique*,
i.e. a subgraph where all nodes are connected;
and (II) they are optimally colorable in O(n²)
with respect to the number of nodes.
This leads to the simpler algorithm shown in figure 5, where,
if destruction of the SSA property is delayed until after register allocation,
all spilling can be done upfront.
Whether spilling is necessary can be determined by
looking at the size of the largest clique of the interference graph,
which equals the maximum number of variables live at any point in the program,
and seeing if it is larger than the number of available registers.
To see why this all is possible one needs to be aware of the dominance property.

<figure>
<img src="{{site.url}}/assets/ssa-regalloc-summary/ssa-regalloc.svg" alt="SSA-based register allocation" style="display: block; margin: auto;" />
<figcaption>
Figure 5:
Register allocation algorithm for programs in SSA form.
Unlike for non-SSA programs the steps may be done separately.
</figcaption>
</figure>

*Dominance* is a property of SSA.
A node *A* of an SSA CFG is said to *dominate* a node *B* (*A ≼ B*)
if it is impossible to reach *B* without first executing *A*,
see figure 6.
Two useful lemmas about the relation between dominance and interference
given by Budimlic et al.[^budimlic02] are,
where *𝓓ᵥ* is the definition of *v*:

1. If variables *u*, *v* interfere then either
   *𝓓ᵤ ≼ 𝓓ᵥ* or *𝓓ᵥ ≼ 𝓓ᵤ*.
1. If *u*, *v* interfere and *𝓓ᵤ ≼ 𝓓ᵥ* then *u* is live at *𝓓ᵥ*.

These enable efficient coloring of the interference graph.

<figure>
<img src="{{site.url}}/assets/ssa-regalloc-summary/dominance.svg" alt="Example of dominance property" style="display: block; margin: auto;" />
<figcaption>
Figure 6:
In this example
the definition of <code>i</code> dominates the definition of <code>j</code>
since all program executions reaching the definition of <code>j</code>
passes through the definition of <code>i</code>.
The live ranges of the two variables are given to the left.
Note that the ranges overlap, i.e. the variables interfere.
</figcaption>
</figure>

Picture this algorithm for graph coloring explained in the paper:
(I) Remove nodes one by one by always choosing a node *v*
where *v* and its neighbors form a clique,
continue until all nodes are exhausted; and then
(II) insert the nodes back in reverse order while coloring greedily,
i.e. giving the new node a color not shared by its neighbors.
The idea is that when reinserting a node,
it together with all its already-colored neighbors will form a clique,
the size of which is bounded by the size of the largest clique.
It is clear that this gives a valid coloring,
with the number of colors equal to the size of the largest clique,
in linear time.
(The number of colors has been bounded by the number of available registers.)
The question is whether such a removal order exists.
The claim is that postorder traversal of the dominance tree yields such an order.
As a side note, known from graph theory is that
the graphs for which such orderings exist are the triangulated graphs
and that this algorithm will in fact give an optimal coloring.
The paper goes on to prove the claim.

To reiterate, we should be able to remove a variable *v*
if all variables whose definitions are dominated by *𝓓ᵥ*
have already been removed.
That would require that *v* and its neighbors form a clique.
Assume not, i.e. *v* has two neighbors *a*, *b* that do not interfere.
For *a* we must have either *𝓓ₐ ≼ 𝓓ᵥ* or *𝓓ᵥ ≼ 𝓓ₐ* due to the first lemma,
but the latter is impossible since *a* would then have been removed.
Since *a*, *v* interfere - they are neighbors in interference graph -
and *𝓓ₐ ≼ 𝓓ᵥ*, the second lemma says *a* must be live at *𝓓ᵥ*.
But the same holds for *b*, meaning *a*, *b* are both live at the point *𝓓ᵥ* of the program,
and so by definition they interfere which contradicts the assumption.
Thus just by walking the dominance tree in postorder
one can color the graph greedily.

The paper then proposes heuristic algorithms for the other parts of register allocation:
Choosing variables to spill and coalescing copies.
For the former,
it extends Belady's MIN algorithm[^belady66] for spilling in basic blocks[^guo03]
to work on the entire program.
Belady's MIN algorithm spills the variable whose next use is farthest away.
This distance is estimated by taking the minimum over all control flow paths
that reach the use.
When combining the sets of variables not spilled
after the last instruction of each basic block,
it has to check that each such set contains all variables
live into each successor block or otherwise insert reloads,
i.e. instructions that move the variable from the stack into a register.

Furthermore the paper gives a heuristic algorithm for coalescing copies.
Coalescing, the act of ensuring the source and destination of a copy instruction
be allocated in the same register, making the copy superfluous,
has been omitted from this summary for the sake of brevity.
Read the paper if interested.

The later paper Pereira and Palsberg[^pereira05] solves some of the shortcomings of this paper
related to real world uses.
One such shortcoming is pre-coloring of the graph:
E.g. the AMD64 DIV instruction always outputs into the RAX and RDX registers,
use two of those and one of the respective destination variables
will need to be spilled if they interfere,
possibly breaking the triangulated property of the interference graph.
Like how SSA basic block parameters can be equated with
copies of the arguments to the parameter variables,
even more copies are inserted -
between each instruction and at the end of each basic block -
to get so called *elementary form* programs.
These elementary programs and their elementary interference graphs
then have even nicer properties than triangulated interference graphs.

The result of using elementary programs is a register allocator
usable as a replacement for LLVM:s non-graph coloring register allocator,
comparable in terms of speed,
that produces x86 code of similar quality
to a slower state-of-the-art graph coloring register allocator.

[^hack06]: Sebastian Hack, Daniel Grund, and Gerhard Goos. "Register allocation for programs in SSA-form". In: International Conference on Compiler Construction. Springer. 2006, pp. 247–262.
[^briggs94]: Preston Briggs, Keith D Cooper, and Linda Torczon. "Improvements to graph coloring register allocation". In: ACM Transactions on Programming Languages and Systems (TOPLAS) 16.3 (1994), pp. 428–455.
[^pereira05]: Fernando Magno Quintao Pereira and Jens Palsberg. "Register allocation via coloring of chordal graphs". In: Asian Symposium on Programming Languages and Systems. Springer. 2005, pp. 315–329.
[^budimlic02]: Zoran Budimlic et al. "Fast copy coalescing and live-range identification". In: ACM SIGPLAN Notices 37.5 (2002), pp. 25–32.
[^belady66]: Laszlo A. Belady. "A study of replacement algorithms for a virtual-storage computer". In: IBM Systems journal 5.2 (1966), pp. 78–101.
[^guo03]: Jia Guo, Maria Jesus Garzaran, and David Padua. "The power of Belady’s algorithm in register allocation for long basic blocks". In: International Workshop on Languages and Compilers for Parallel Computing. Springer. 2003, pp. 374–389.

[JoeQ]: https://joeq.sourceforge.net/
