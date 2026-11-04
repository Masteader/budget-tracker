import type {Template} from '../props';
import {DailyTip} from './DailyTip';
import {FeatureDemo} from './FeatureDemo';
import type {TemplateDefinition} from './media';
import {MythVsFact} from './MythVsFact';

export const TEMPLATES: Record<Template, TemplateDefinition> = {FeatureDemo, DailyTip, MythVsFact};
