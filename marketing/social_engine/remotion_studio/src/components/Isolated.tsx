import React from 'react';
import {groupWordRuns, localizeDigits, splitForIsolation} from '../lib/text';
import type {Digits, Language} from '../props';

/** Words in their reel's order, with any run of foreign words in a row of its own direction. */
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
	return (
		<>
			{groupWordRuns(items, textOf, language).map((run) =>
				run.direction ? (
					<span
						key={positions.get(run.items[0] as T)}
						data-direction-run={run.direction}
						dir={run.direction}
						style={{display: 'inline-flex', flexWrap: 'wrap', justifyContent: 'center', columnGap: gap}}
					>
						{run.items.map(place)}
					</span>
				) : (
					run.items.map(place)
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
