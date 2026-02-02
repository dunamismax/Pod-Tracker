import { MD3DarkTheme, MD3LightTheme } from 'react-native-paper';
import { colors } from '@/theme/tokens';

export const paperLightTheme = {
  ...MD3LightTheme,
};

export const paperDarkTheme = {
  ...MD3DarkTheme,
  colors: {
    ...MD3DarkTheme.colors,
    background: colors.background,
    surface: colors.surface,
    surfaceVariant: colors.surfaceVariant,
    outline: colors.outline,
    primary: colors.primary,
    secondary: colors.secondary,
    tertiary: colors.accent,
    error: colors.error,
    onBackground: colors.textHigh,
    onSurface: colors.textHigh,
    onSurfaceVariant: colors.textLow,
  },
};
