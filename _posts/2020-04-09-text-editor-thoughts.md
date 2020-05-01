---
layout: post
title: "Text Editor Thoughts"
date: 2020-04-09
description: "Something something"
---

I love vi-style modal keybindings, I do not love Vim.

There are tons resources justifying the vi model
and it seems to be every tech blogger's rite of passage to
to do a write-up on their top ten favourite plugins.
Yet I still hear of too many who do not *get it*
and so I will summarize my reasons.
Modality enables commands that both
compose incredibly well -
any operator can be combined with any motion;
and are readily accessible on the letter keys,
not requiring stretching your fingers for any modifiers.
In fact, it is so well-suited for text editing that you can often 
replace usages of language specific commands with
combinations of non-contextual vi commands,
for example swapping arguments in C-likes with `df,;p`,
removing all arguments in a call with `di)`
or rewriting the latter half of a function with `c]}`.
You might have thought that macros in other editors were cool
but in vi they are elevated to a whole other level:
The ways you normally edit text already encourage repeatability
compared to mouse-centric workflows where
clicking where to insert next does not carry any semantic meaning.
Also actually using macros for "routine edits" is the most natural thing
due to how few keystrokes they require.
Say you were writing some math in LaTeX and two dates or whatever
needed to be wrapped with `\text{...}`.
Then just `qqi\text{<Esc>a}<Esc>qf2@q` will do the trick.
All this would be impossible to recreate in a non-modal editor.

It is undeniable that Vim has been influential in forwarding the legacy of vi,
and it has introduced many features such as
reliable undo, build-in help and a system for plugins,
the absence of which would be felt to say the least.
It has been my primary editor for the past five years.

Equate stock Vim and plugins.

I find the Neovim gatekeeping ridiculous.

Let us talk about Lua?

Now the only thing that remains for this trainwreck of an article to be complete is a quote
from the *numero uno* television show for intellectuals:

> Vim's not a villain, Summer, but it shouldn't be your hero.
