<!DOCTYPE html>
<html lang="en" class="h-full">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Magic Pod Dashboard</title>
        @vite(['resources/css/app.css', 'resources/js/app.js'])
        @fluxAppearance
        @livewireStyles
    </head>
    <body class="min-h-screen bg-zinc-100 text-zinc-900 antialiased">
        <header class="border-b border-zinc-200 bg-white">
            <div class="mx-auto flex w-full max-w-5xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
                <a href="{{ auth()->check() ? route('dashboard') : route('login') }}" class="font-semibold tracking-tight">
                    Magic Pod Dashboard
                </a>
                <div class="flex items-center gap-3">
                    @auth
                        <flux:text class="hidden text-sm text-zinc-600 sm:inline">{{ auth()->user()->email }}</flux:text>
                        <form method="POST" action="{{ route('logout') }}">
                            @csrf
                            <flux:button type="submit" variant="ghost" size="sm" class="cursor-pointer">
                                Sign out
                            </flux:button>
                        </form>
                    @else
                        <flux:link href="{{ route('login') }}" wire:navigate>Sign in</flux:link>
                    @endauth
                </div>
            </div>
        </header>

        <main class="mx-auto w-full max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
            {{ $slot }}
        </main>

        @livewireScripts
        @fluxScripts
    </body>
</html>
