@extends('layouts.pod')

@section('content')
    <section class="mx-auto w-full max-w-xl">
        <div class="auth-panel">
            <p class="ui-kicker">Authentication</p>
            <flux:heading size="xl" class="mt-2 text-zinc-100">Sign in</flux:heading>
            <flux:subheading class="mt-2 text-zinc-400">
                Use your email and password to access your pod dashboard.
            </flux:subheading>

            @if (session('status'))
                <div x-data="{ visible: true }" x-show="visible" x-transition class="mt-4">
                    <flux:callout icon="check-circle" variant="secondary">
                        <flux:callout.heading>{{ session('status') }}</flux:callout.heading>
                        <x-slot name="controls">
                            <flux:button type="button" icon="x-mark" variant="ghost" x-on:click="visible = false" />
                        </x-slot>
                    </flux:callout>
                </div>
            @endif

            <form method="POST" action="{{ route('login.store') }}" class="mt-6 space-y-4">
                @csrf

                <flux:input
                    name="email"
                    :label="__('Email')"
                    type="email"
                    autocomplete="email"
                    :value="old('email')"
                    required
                    autofocus
                    placeholder="email@example.com"
                />
                <flux:error name="email" />

                <flux:input
                    name="password"
                    :label="__('Password')"
                    type="password"
                    autocomplete="current-password"
                    viewable
                    required
                />
                <flux:error name="password" />

                <flux:checkbox
                    name="remember"
                    value="1"
                    :checked="(bool) old('remember')"
                    label="Remember me on this device"
                />

                <flux:button type="submit" variant="primary" class="w-full cursor-pointer" data-test="login-button">
                    Sign in
                </flux:button>
            </form>

            <p class="mt-5 text-sm text-zinc-400">
                Forgot your password?
                <flux:link href="{{ route('password.request') }}" class="text-cyan-200">Reset it here</flux:link>.
            </p>

            <p class="mt-2 text-sm text-zinc-400">
                New here?
                <flux:link href="{{ route('register') }}" class="text-cyan-200">Create an account</flux:link>.
            </p>
        </div>
    </section>
@endsection
