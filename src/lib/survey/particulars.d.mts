export type Declaration = 'has_medical_condition' | 'drinks_alcohol' | 'smokes' | 'on_treatment';
export const DECLARATIONS: Declaration[];

export interface ParticularsDraft {
  first_name: string; last_name: string; phone: string; email: string; date_of_birth: string;
  sex: string; occupation: string; others_text: string; source_option_id: string; source_details: string;
  treatment_list: string;
  has_medical_condition: boolean | null; drinks_alcohol: boolean | null; smokes: boolean | null;
  on_treatment: boolean | null;
  symptoms: Record<string, string>;
}

export function seedParticulars(
  survey: Record<string, any> | null | undefined,
  symptoms: { option_id: string; duration_text?: string | null }[] | null | undefined,
): ParticularsDraft;

export function particularsChanges(seed: ParticularsDraft, draft: ParticularsDraft): Record<string, any>;

export function particularsNeedReason(
  changes: Record<string, any>,
  opts?: { hasCustomer?: boolean; customerDob?: string | null },
): boolean;

export function dobChangeAllowed(
  changes: Record<string, any>,
  opts?: { hasCustomer?: boolean; customerDob?: string | null; role?: string | null },
): boolean;

export function answerLabel(v: boolean | null | undefined): string;
