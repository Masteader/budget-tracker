import {spring as remotionSpring} from 'remotion';

type SpringOptions = Parameters<typeof remotionSpring>[0];

const SETTLED_AFTER_SECONDS = 3;

/** Remotion's spring steps through every frame up to `frame`, so stop counting once it has settled. */
export const spring = (options: SpringOptions): number =>
	remotionSpring({...options, frame: Math.min(options.frame, SETTLED_AFTER_SECONDS * options.fps)});
