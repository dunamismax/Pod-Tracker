<!DOCTYPE html>
<html lang="en" class="h-full dark">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Magic Pod Dashboard</title>
        @vite(['resources/css/app.css', 'resources/js/app.js'])
        @livewireStyles
    </head>
    <body class="min-h-screen text-zinc-100 antialiased">
        <div class="ui-shell">
            <div class="pointer-events-none absolute inset-0 -z-10 overflow-hidden">
                <div class="ui-grid absolute inset-0 opacity-45"></div>
                <div class="absolute -left-24 top-0 h-72 w-72 rounded-full bg-cyan-400/15 blur-3xl"></div>
                <div class="absolute right-0 top-20 h-96 w-96 rounded-full bg-indigo-500/20 blur-3xl"></div>
                <div class="absolute bottom-0 left-1/3 h-80 w-80 rounded-full bg-emerald-400/10 blur-3xl"></div>
            </div>

            <header class="sticky top-0 z-30 border-b border-white/10 bg-zinc-950/75 backdrop-blur-xl">
                <div class="mx-auto flex w-full max-w-6xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
                    <a href="{{ auth()->check() ? route('dashboard') : route('login') }}" class="inline-flex items-center gap-3">
                        <span class="inline-flex size-9 items-center justify-center rounded-xl border border-cyan-300/45 bg-cyan-300/10 text-xs font-black tracking-[0.18em] text-cyan-200">
                            MP
                        </span>
                        <span class="text-sm font-semibold tracking-[0.04em] text-zinc-100 sm:text-base">Magic Pod Dashboard</span>
                    </a>
                    <div class="flex items-center gap-2 sm:gap-3">
                        <flux:button
                            type="button"
                            variant="ghost"
                            size="sm"
                            icon="moon"
                            class="cursor-pointer"
                            x-data="{ dark: document.documentElement.classList.contains('dark') }"
                            x-on:click="dark = ! dark; document.documentElement.classList.toggle('dark', dark)"
                            x-bind:aria-label="dark ? 'Switch to light theme' : 'Switch to dark theme'"
                        >
                            <span class="hidden sm:inline" x-text="dark ? 'Dark' : 'Light'"></span>
                        </flux:button>
                        @auth
                            <flux:text class="hidden text-sm text-zinc-400 sm:inline">{{ auth()->user()->email }}</flux:text>
                            <form method="POST" action="{{ route('logout') }}">
                                @csrf
                                <flux:button type="submit" variant="ghost" size="sm" class="cursor-pointer">
                                    Sign out
                                </flux:button>
                            </form>
                        @else
                            <flux:link href="{{ route('login') }}" class="text-zinc-300 hover:text-zinc-100">Sign in</flux:link>
                            @if (Route::has('register'))
                                <flux:link href="{{ route('register') }}" class="text-zinc-300 hover:text-zinc-100">Create account</flux:link>
                            @endif
                        @endauth
                    </div>
                </div>
            </header>

            <main class="mx-auto w-full max-w-6xl px-4 py-10 sm:px-6 lg:px-8">
                @isset($slot)
                    {{ $slot }}
                @else
                    @yield('content')
                @endisset
            </main>
        </div>

        @livewireScripts
        @fluxScripts
    </body>
</html>
