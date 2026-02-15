@extends('layouts.pod')

@section('content')
    <section class="mx-auto w-full max-w-xl">
        <div class="auth-panel">
            <p class="ui-kicker">Authentication</p>
            <flux:heading size="xl" class="mt-2 text-zinc-100">Forgot password</flux:heading>
            <flux:subheading class="mt-2 text-zinc-400">
                Enter your email and we will send you a password reset link.
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

            <form method="POST" action="{{ route('password.email') }}" class="mt-6 space-y-4">
                @csrf

                <flux:input
                    name="email"
                    :label="__('Email')"
                    type="email"
                    autocomplete="email"
                    :value="old('email')"
                    required
                    placeholder="email@example.com"
                />
                <flux:error name="email" />

                <flux:button type="submit" variant="primary" class="w-full cursor-pointer" data-test="send-reset-link-button">
                    Email reset link
                </flux:button>
            </form>

            <p class="mt-5 text-sm text-zinc-400">
                Remembered it?
                <flux:link href="{{ route('login') }}" class="text-cyan-200">Back to sign in</flux:link>.
            </p>
        </div>
    </section>
@endsection
