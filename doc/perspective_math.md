# The math behind perspective in .ass subtitles
This page writes up most of the math involved in the various perspective scripts floating around.
It starts with explaining how [perspective.py](https://github.com/TypesettingTools/Perspective) and its Moonscript version [perspective.moon](https://github.com/Alendt/Aegisub-Scripts/blob/master/perspective.moon) work, and goes on to explain what I found out on top of this and how I used it in [Perspective-motion](https://github.com/Zahuczky/Zahuczkys-Aegisub-Scripts/tree/daily_stream) and my hopefully eventually upcoming improved perspective script.

This is mostly a compiled version of the long rundown I gave on Discord, so it's not too formal or polished yet. Still, it's better than no documentation at all. A more formal write-up might follow eventually.

## How does perspective.py or (Alendt's) Perspective.moon work?
Perspective.moon takes the four corner points of a quadrilateral, and outputs transform tags that would transform text to have perspective matching that quadrilateral. That is, assuming that the given 2D quad is the 2D projection of a three-dimensional rectangle, the tags will transform the text into the same 3D plane as that rectangle.

To see how this works, let's remember what transform tags are applied in what order:
1. `\fax` and `\fay` (`\fay` is useless so let's just ignore it)
2. `\fscx` and `\fscy`
3. `\frz`
4. `\frx`, and then `\fry`
5. The previous step turned this into a 3D object, so we project back into 2D. This is done by adding $312.5$ to all $z$ coordinates and then projecting all points to the $z=312.5$ plane by multiplying each point by $312.5$ divided by their $z$ coordinate.
(Geometrically, after we translated, we draw a line from each point to the origin $(0, 0, 0)$ and intersect that line with the $z=312.5$ plane)

Note that if `\fax` and `\fay` are $0$, then after step 4 the text is a (3D) rectangle.
If `\fax` is not $0$, then it's only a parallelogram.

Suppose we now want to find tags that transform a rectangle such that the quad resulting after steps 1-5 is the quad we were given. We start with the quad and undo the steps 5-1 one by one. This is done by the [`unrot`](https://github.com/Alendt/Aegisub-Scripts/blob/476e6309c0bc4baac736ba17b7dcc3969266a54e/perspective.moon#L70) function in perspective.moon, which is also the only really relevant function in the script. The others are ugly exhaustive searches, more on that later.

Now, the first step we need to undo is step 5, the projection. Given a 2D quad in the $z=312.5$ plane, we want to find a 3D parallelogram that projects onto that quad.
Equivalently, given such a 2D quad, we can draw the four lines from the origin $(0, 0, 0)$ through its four corners, and find a point on each of these lines, such that the quad that they build is a parallelogram.
It turns out that for each quad there is exactly one such parallelogram, up to scaling.
You can also easily compute it, just by solving the linear system of equations that comes out of this.

Alternatively, perspective.moon uses a nice geometric trick, exploiting that parallelograms are characterized by their diagonals bisecting each other exactly: It starts by computing the "center" of the quad by intersecting the diagonals.
Then, for each of the two diagonals, it multiplies the two corresponding points by a factor such that the areas of the two triangles point-center-origin are equal (by just multiplying on e point by the ratio of these areas, which are computed using the cross product).
The areas being equal is actually equivalent to the lengths of the point-center segments being equal, so this gives us the ratios we want.
Then, the three points are scaled again so that the center ends up where it was originally.
This is done for both diagonals, and the resulting four points make up the parallelogram we wanted.

Now, we've found our parallelogram.
Let's assume for a second that we lucked out and it's a rectangle.
Then, we have a rectangle in 3D space and need to find rotation tags that rotate a 2D rect into the same plane as this 3D rect.
Equivalently, we want to apply y,x,z rotations (in that order; the opposite order to the original transformation) that rotate our 3D rectangle back into a horizontal planar 2D rect.
This is comparatively simple - you just compute the normal vector and do some trigonometry to find the `\fry` and `\frx`. Then you apply that rotation to actually get a 2D rect in the plane, and finally do more trigonometry to find the `\frz` that makes this back into a horizontal rectangle.
And that's it!
We've transformed our quad back into a horizontal 2D rect.
Conversely, if we start out with such a rect (like any text) and apply the corresponding tags, we'll get a quad that matches the perspective of the quad we put in.

This is exactly what perspective.moon does, in its simplest case. But things can get a little more complicated:
First of all, we assumed that we got a rectangle out of our inverse projection computation.
If we don't get a rectangle, but only a parallelogram, then we can in principle repeat all of the same computations to invert `\fry`, `\frx`, `\frz`.
In the end, we'll get a horizontal planar parallelogram.
Then we can just find the `\fax` that turns a rectangle into that parallelogram.
If you run perspective.moon with "Transform for target org", that's exactly what happens.

But `\fax` is ugly and messes up positioning (this is not the only reason - not needing `\fax` is a sign that you've found the right origin, and if you're lucky you can typeset multiple pieces of text with the same tags and origin), so perspective.moon includes code to work around that:
One thing I have glossed over so far is that it's not clear where the (2D) origin point of our quad is.
That is, depending how you translate your input quad in 2D space, you can get different results (well, the unproject-coefficients actually stay the same, but everything else changes).
In particular, if you translate the input quad before doing the unprojection steps, you can get closer to or further away from your unprojected parallelogram becoming a rectangle.
In .ass terms, "Translating the input quad" means changing `\org`, since that's the origin relative to which all projections happen.
So, we can try to search for a value of `\org` that hopefully gives us a rectangle after unprojecting.

Perspective.moon just does that with a lot of brute force searching.
The full form of the `unrot` function takes a quad *and* an `\org` and does all of the computations above.
But after unprojecting, it also computes the `diag_diff` number as $\frac{d_1-d_2}{d_1+d_2}$, where $d_1$ and $d_2$ are the lengths of the diagonals.
The point being that a parallelogram is a rectangle if and only if its diagonals have the same lengths.
So this number ranges from $-1$ to $1$, and it's equal to $0$ if and only if the parallelogram is a rect, so if and only no `\fax` is needed.

So perspective.moon just searches for `\org` points where this `diag_diff` value comes out close to $0$.
It starts by searching in a huge but not very fine range for maxima and minima of `diag_diff`.
Then it searches for a zero of the segment connecting the maximum and minimum.
Then it keeps rotating the segment around one of those points and searches for further zeros.
Finally, out of all candidate points it picks the one which is closest to the actual center of the quad, or the one where the ratio of the rectangle's sides is the closest to the target ratio.

## Improvements upon perspective.moon
First of all, it's possible to turn the `\org` search into more explicit calculations if you do a bit more math.
The `diag_diff` value is harder to handle, but it gets a lot easier if you just take the scalar product of two sides of the parallelogram instead.
This is also $0$ if and only if the parallelogram is a rectangle, but most importantly it's nice and linear.
If you write down all the equations for the unprojection and in the end solve for the scalar product being $0$, it turns out that you always get polynomial equation in two variables of degree at most $2$.
And, in fact, it always cuts out a circle, or in rare cases degenerates to a linear equation.
So you can find actually find optimal `\org` points more precisely.

Moreover, while perspective.moon does the unrot computations I described above and outputs `\org`, `\fax`, and rotation tags, these are also the only tags it outputs.
It doesn't give any `\fscx` or `\fscy` values.
So its output tags don't always transform the text onto the quad exactly - they only transform it into the same plane as the quad.
Since the original scene might have been drawn or rendered with a different focal length than the $312.5$ that .ass uses, the `\fscx` or `\fscy` often need to be adjusted.
For typesetting static scenes this isn't a problem, since you can adjust them manually.
But it becomes crucial when you want to do perspective tracking, since the scaling needs to stay consistent when the perspective changes.

So how do you fix this?
If you just want to transform your text exactly onto some quad, it's simple: You just start by running perspective.moon's calculations.
Once that's done, you run the 3D quad through all the inverse transformations and get a horizontal 2D rect.
Then you can just compare the width and height of that rect with your text, and adjust accordingly.

... actually, this is not what I did in persp-mo.
Mostly because I didn't actually think of that solution back then (tunnel vision after working on other components where this didn't work well), but also because this stops working well as soon as you don't want to transform to the quad, but only to some part of it (see below).
Instead, I did the same computation, just on an infinitesimally small rectangle.
That is, after finding the transform tags, I took the resulting transformation (including projecting) as a mathematical function from the plane to itself and let Mathematica compute the Jacobian (all partial derivatives) to find out how much this scales a rectangle in the $x$ or $y$ direction.
Then, I did the same for the mathematical perspective transformation transforming a 1x1 square to the quad (see below for how to find that), and compared the two scaling factors.
In the end, these approaches are more or less equivalent, but this one is quicker, and a lot fancier.

## Perspective tracking and all the rest
Now, you might think that we figured out scaling now, but that's not yet the full story.
Usually, you don't want your text to fill the whole quad you're tracking from edge to edge (both horizontally and vertically).
You also don't want your text to be positioned precisely at the center of that quad.
You can fix the first point by manually scaling afterward, but the second point needs you to a) track the position of the text properly, so it stays at the same position (in terms of perspective) relative to the moving quad, and b) make the scaling match - if you have a 3D quad, then sections closer to the screen will be bigger than sections further away, and this ratio changes when the quad moves or rotates.

Pragmatically, you can do part a) by just tracking the point with Mocha and Aegisub-Motion, if that's feasible.
But part b) needs more work.

So, the remaining question is more or less this: Given two quads, and a point on the first quad, what's the "corresponding" point on the second quad?
Or, how do I compute the "perspective transformation function" (if you care, this means a function of the form $(x, y) \mapsto \left( \frac{a_1+a_2x+a_3y}{c_1+c_2x+c_3y}, \frac{b_1+b_2x+b_3y}{c_1+c_2x+c_3y} \right)$, or if you're a math guy, an element of the projective linear group $\mathbb P\mathrm{GL}_3$) from the 2D plane to itself that maps one quad onto the other?
In fact, does there even exist such a function?!

So, yes, projective geometry tells us that for any two (non-degenerate) quads (with numbered corners), there is exactly one projective transformation mapping the corners of one quad to the other's.
As for how to compute them, let's just reduce this to a simpler case: Start by for any quad finding a projective transformation mapping that quad to the 1x1 square, as well as its inverse.
Then you can go from any quad to any other quad by going from the first quad to the 1x1 square to the second quad.

And if you think about it a bit, we've already found such a transformation!
After all, we've found transform tags transforming such a 1x1 square to any quad, and we can also easily invert each of the transformations involved (projecting is the only hard part there you just draw the line through the point and the origin, and intersect it with the plane through the 3D rect).
That comes out to be a perfect projective transformation.

However, a) I didn't realize that at first and, b) computing the transformation involved taking trigonometric functions of the quad's coordinates, which isn't nice.
Actually, the main theorem of projective geometry works over any field, so the transformation should just be expressible as a rational function.
You could write down the transformation symbolically and simplify everything, or you can just take an approach from scratch:

Another fun part of projective geometry is the cross-ratio: If you have four points $A, B, C, D$ on a line in that order, their cross-ratio is defined as $\frac{\lvert AC\rvert \cdot \lvert BD\rvert}{\lvert AD\rvert\cdot\lvert BC\rvert}$.
The cool part is that one of these points is allowed to lie "at infinity" (this makes sense in projective geometry): If $D$ is the point at infinity, then $\lvert BD\rvert$ "cancels" with $\lvert AD\rvert$ and the cross-ratio is just $\frac{\lvert AC\rvert}{\lvert BC\rvert}$.

So, cross-ratios are fun and all, but the whole reason why they're so important is that they're preserved under projective transformations (just like a rotation preserves lengths, for example).
So if you have four such points $A, B, C, D$, and a projective transformation $\varphi$, then the cross-ratio of $\varphi(A), \varphi(B), \varphi(C), \varphi(D)$ will be the same as the cross-ratio of $A, B, C, D$.

And you can use these to figure out the perspective transformation: If you want to transform a quad $ABCD$ to the 1x1 square (call the transformation $\varphi$), you can intersect the lines through two opposite sides $AB$ and $CD$ and call the intersection $F$ (suppose $B$ lies between $A$ and $F$ - all these assumptions cancel out later).
Given a point $P$ on the quad, you can intersect $AD$ and $BC$ with the line through $PF$.
If the intersection points are $S$ and $T$, you can find the $x$ coordinate of $\varphi(P)$ using the cross-ratio of $S,P,T,F$.
The other computations and the inverse work similarly.

So I typed all of that into Mathematica and let it compute and simplify all of that into rational functions involving the coordinates of the quad and the point.
Then I copy-pasted the output into the code.
This is found in both Perspective-motion and my [WIP perspective libary](../modules/arch/Perspective.moon).

So with this we can find out how a point on the quad moves if the quad moves, so we can perspective track a point.
And with this, we can also compute how scaling works away from the center of the quad: Like before, you can take the transformation mapping the quad to the unit square, and take the Jacobian *at* the point you're tracking.
Then compare that to the Jacobian of the .ass transform tags (that one still has to be taken at the (relative) origin) transforming text around that point to the proper perspective.
So, I let Mathematica also compute the derivatives of these rational functions, and also paste those into the code - and then that's finally it.

That's more or less where we're at with persp-mo right now.
Some other bits:
- The `\org` search (neither perspective.moon's version nor mine) isn't involved - we just do everything with `\fax` right now
- `\fax` messes up positioning, but at least in a predictable manner. So we just compute how much the position is offset and correct for it with `\pos`, while keeping `\org` where the position *should* be
- Some fun facts: I went through a bunch of iterations with this.
  Before I bit the bullet and computed the transformations manually, I tried to instead find a focal length such that unprojecting would immediately output a rectangle when the origin was at the center of the screen (since `\org` searching on top of that would be really hard).
  I did this by assuming that the original 3D rectangle's aspect ratio would stay constant throughout and doing least-squares optimization.
  I'm glad I scrapped that, since the current solution is much cleaner and works in full generality.
  But I know that this code was used for at least one actual sign, so it wasn't completely useless.

Finally, with this it's possible to transform arbitrary quads to arbitrary quads. So now it's also possible to do things like
- Rotate an already perspecified line relative to the plane it's supposed to be in, so you can give something `\frz` (or any other tranformation) after adding perspective
- Shift and already perspectified line in its plane
- Take a 3D line and make it transform to the same quad, scaled by a factor. This would correctly resample rotations to higher resolutions.

Hopefully, my better perspective will eventually be able to do all of these, once it's completed.