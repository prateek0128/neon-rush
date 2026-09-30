import type { ButtonHTMLAttributes, ReactNode } from 'react'
import { Link } from 'react-router-dom'

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & { children: ReactNode; variant?: 'primary' | 'secondary' | 'ghost'; to?: string; fullWidth?: boolean }

export function Button({ children, variant = 'primary', to, fullWidth = false, className = '', ...props }: ButtonProps) {
  const classes = `button button-${variant}${fullWidth ? ' button-full' : ''}${className ? ` ${className}` : ''}`
  if (to) return <Link className={classes} to={to}>{children}</Link>
  return <button className={classes} {...props}>{children}</button>
}
