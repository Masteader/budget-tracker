import React from 'react';
import {groupWordRuns, localizeDigits, splitForIsolation} from '../lib/text';
import type {Digits, Language} from '../props';

/** A space between flex items draws nothing, and keeps the text readable as text. */
const spaced = (nodes: React.ReactNode[]): React.ReactNode[] =>
	nodes.flatMap((node, index) => (index === 0 ? [node] : [' ', node]));

/** Words in their line's order, with any run of foreign words in a row of its own direction. */
export const WordRuns = <T,>({
	items,
	textOf,
	language,
	gap,
	renderWord,
}: {
	items: T[];
	textOf: (item: T) => string;
	language: Language;
	gap: number;
	renderWord: (item: T, position: number) => React.ReactNode;
}) => {
	const positions = new Map(items.map((item, position) => [item, position]));
	const place = (item: T) => renderWord(item, positions.get(item) ?? 0);
	const placeAtom = (atom: T[]) =>
		atom.length > 1 ? (
			<span
				key={`atom-${positions.get(atom[0] as T)}`}
				data-keep-together="true"
				style={{display: 'inline-flex', whiteSpace: 'nowrap', columnGap: gap}}
			>
				{spaced(atom.map(place))}
			</span>
		) : (
			place(atom[0] as T)
		);
	return (
		<>
			{spaced(
				groupWordRuns(items, textOf, language).map((run) =>
					run.direction ? (
						<span
							key={`run-${positions.get(run.atoms[0]?.[0] as T)}`}
							data-direction-run={run.direction}
							dir={run.direction}
							style={{display: 'inline-flex', flexWrap: 'wrap', justifyContent: 'center', columnGap: gap}}
						>
							{spaced(run.atoms.map(placeAtom))}
						</span>
					) : (
						<React.Fragment key={`run-${positions.get(run.atoms[0]?.[0] as T)}`}>
							{spaced(run.atoms.map(placeAtom))}
						</React.Fragment>
					),
				),
			)}
		</>
	);
};

/** Text with its digits from config and <bdi> around the runs that need it. */
export const Isolated: React.FC<{text: string; language: Language; digits: Digits}> = ({
	text,
	language,
	digits,
}) => (
	<>
		{splitForIsolation(localizeDigits(text, digits), language).map((run, index) =>
			run.isolate ? (
				<bdi key={index}>{run.text}</bdi>
			) : (
				<React.Fragment key={index}>{run.text}</React.Fragment>
			),
		)}
	</>
);
