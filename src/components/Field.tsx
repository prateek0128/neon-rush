import type { InputHTMLAttributes, ReactNode } from 'react'

type FieldProps = InputHTMLAttributes<HTMLInputElement> & { label: string; hint?: string; leading?: ReactNode }

export function Field({ label, hint, leading, id, ...props }: FieldProps) {
  const fieldId = id ?? props.name ?? label.toLowerCase().replaceAll(' ', '-')
  return <div className="field-wrap">
    <label className="field-label" htmlFor={fieldId}>{label}</label>
    <div className={`input-frame${leading ? ' has-leading' : ''}`}>
      {leading && <span className="input-leading" aria-hidden="true">{leading}</span>}
      <input id={fieldId} {...props} />
    </div>
    {hint && <p className="field-hint">{hint}</p>}
  </div>
}
