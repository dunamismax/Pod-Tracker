import { cn } from '~/lib/utils';

type ButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  color?: 'neutral' | 'warning';
  loading?: boolean;
  size?: 'default' | 'lg' | 'xl';
  variant?: 'default' | 'soft';
};

type ButtonColor = NonNullable<ButtonProps['color']>;
type ButtonVariant = NonNullable<ButtonProps['variant']>;
type ButtonSize = NonNullable<ButtonProps['size']>;

const sizeClasses: Record<ButtonSize, string> = {
  default: 'px-4 py-2 text-sm',
  lg: 'px-5 py-2.5 text-sm',
  xl: 'px-6 py-3 text-base',
};

function colorClasses(color: ButtonColor, variant: ButtonVariant) {
  if (color === 'warning' && variant === 'default') {
    return 'bg-amber-500 text-white hover:bg-amber-400 active:bg-amber-600';
  }
  if (color === 'neutral' && variant === 'soft') {
    return 'bg-white/10 text-slate-200 hover:bg-white/15 active:bg-white/20';
  }
  if (color === 'neutral' && variant === 'default') {
    return 'bg-slate-700 text-slate-100 hover:bg-slate-600 active:bg-slate-800';
  }
  return 'bg-amber-500 text-white hover:bg-amber-400 active:bg-amber-600';
}

export function Button({
  className,
  color = 'warning',
  disabled,
  loading,
  size = 'default',
  variant = 'default',
  children,
  ...props
}: ButtonProps) {
  return (
    <button
      className={cn(
        'inline-flex cursor-pointer items-center gap-2 rounded-lg font-medium transition',
        sizeClasses[size],
        colorClasses(color, variant),
        (disabled || loading) && 'pointer-events-none opacity-50',
        className,
      )}
      disabled={disabled || loading}
      {...props}
    >
      {loading && (
        <svg className="h-4 w-4 animate-spin" fill="none" viewBox="0 0 24 24" aria-hidden="true">
          <circle
            className="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            strokeWidth="4"
          />
          <path
            className="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
          />
        </svg>
      )}
      {children}
    </button>
  );
}
