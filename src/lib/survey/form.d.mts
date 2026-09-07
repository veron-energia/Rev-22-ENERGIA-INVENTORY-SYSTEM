export type SurveyField =
  | 'first_name'
  | 'date_of_birth'
  | 'phone'
  | 'email'
  | 'source_option_id'
  | 'source_details'
  | 'signature_data';

export const FIELD_ORDER: SurveyField[];

export interface SurveyFormState {
  first_name: string;
  last_name: string;
  full_name: string;
  date_of_birth: string;
  age: string;
  sex: string;
  phone: string;
  email: string;
  occupation: string;
  source_option_id: string;
  source_details: string;
  event_name: string;
  has_medical_condition: boolean | null;
  drinks_alcohol: boolean | null;
  smokes: boolean | null;
  on_treatment: boolean | null;
  treatment_list: string;
  others_text: string;
  consent_newsletter_email: boolean;
  consent_marketing_email: boolean;
  consent_marketing_sms: boolean;
  consent_marketing_phone: boolean;
  signature_data: string;
  signed_date: string;
}

export function makeInitialForm(signedDate: string): SurveyFormState;

export interface DobParts {
  d: string;
  m: string;
  y: string;
}

export type DobStatus = 'empty' | 'partial' | 'invalid' | 'valid';

export interface DobResult {
  status: DobStatus;
  iso: string;
}

export function parseDob(parts: DobParts, today?: Date): DobResult;

export interface SurveyTick {
  on: boolean;
  duration: string;
}

export interface DirtyInput {
  form: SurveyFormState;
  dob: DobParts;
  ticks: Record<string, SurveyTick>;
  phoneTouched: boolean;
}

export function isSurveyDirty(cur: DirtyInput, initialForm: SurveyFormState): boolean;

export interface ValidateInput {
  form: SurveyFormState;
  dob: DobResult;
  phoneValid: boolean;
  requireSource: boolean;
  sourceRequiresDetails: boolean;
}

export function validateSurvey(input: ValidateInput): Partial<Record<SurveyField, string>>;

export interface MappedServerError {
  field?: SurveyField;
  scope?: 'identity' | 'form';
  message: string;
}

export function mapServerError(raw: string): MappedServerError;
