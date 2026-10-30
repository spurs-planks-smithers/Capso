// Text that element evidence may record for one page element.
// Rule: docs/decisions/2026-10-30-chrome-element-evidence-labels.md.
export const fieldRoles=['textbox','searchbox','combobox','listbox','checkbox','radio','slider','spinbutton','switch'];

export interface CaptionSource {
  tag:string;
  /** Value of the role attribute, possibly several tokens. */
  role:string;
  ariaLabel:string|null;
  ownText:string;
  /** The element sits inside a <label>. */
  insideLabel:boolean;
  /** The element sits inside an element with a field role. */
  insideFieldRole:boolean;
}

export function hasFieldRole(role:string):boolean {
  return role.toLowerCase().split(/\s+/).some(token=>fieldRoles.includes(token));
}

/** Returns the raw caption for an element, or an empty string when it names or holds a field. */
export function evidenceCaption(source:CaptionSource):string {
  if(source.tag.toLowerCase()==='label'||source.insideLabel||source.insideFieldRole||hasFieldRole(source.role))return '';
  return source.ariaLabel||source.ownText;
}
