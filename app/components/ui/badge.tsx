import { cn } from '~/lib/utils';

type BadgeProps = {
  children: React.ReactNode;
  className?: string;
  color?: 'info' | 'neutral' | 'warning';
  variant?: 'outline' | 'soft';
};

type BadgeColor = NonNullable<BadgeProps['color']>;
type BadgeVariant = NonNullable<BadgeProps['variant']>;

function colorClasses(color: BadgeColor, variant: BadgeVariant) {
  if (color === 'info' && variant === 'soft') {
    return 'bg-cyan-500/15 text-cyan-200';
  }
  if (color === 'warning' && variant === 'soft') {
    return 'bg-amber-500/15 text-amber-200';
  }
  if (color === 'neutral' && variant === 'soft') {
    return 'bg-white/10 text-slate-300';
  }
  if (color === 'neutral' && variant === 'outline') {
    return 'border border-white/20 text-slate-300';
  }
  return 'bg-white/10 text-slate-300';
}

export function Badge({ children, className, color = 'neutral', variant = 'soft' }: BadgeProps) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
        colorClasses(color, variant),
        className,
      )}
    >
      {children}
    </span>
  );
}
