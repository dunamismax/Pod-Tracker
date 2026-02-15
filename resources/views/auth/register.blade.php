@extends('layouts.pod')

@section('content')
    <section class="mx-auto w-full max-w-xl">
        <div class="auth-panel">
            <p class="ui-kicker">Authentication</p>
            <flux:heading size="xl" class="mt-2 text-zinc-100">Create account</flux:heading>
            <flux:subheading class="mt-2 text-zinc-400">
                Create your account to manage pods and events.
            </flux:subheading>

            <form method="POST" action="{{ route('register.store') }}" class="mt-6 space-y-4">
                @csrf

                <flux:input
                    name="name"
                    :label="__('Name')"
                    type="text"
                    :value="old('name')"
                    required
                    autocomplete="name"
                    placeholder="Your name"
                />
                <flux:error name="name" />

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

                <flux:input
                    name="password"
                    :label="__('Password')"
                    type="password"
                    autocomplete="new-password"
                    viewable
                    required
                />
                <flux:error name="password" />

                <flux:input
                    name="password_confirmation"
                    :label="__('Confirm password')"
                    type="password"
                    autocomplete="new-password"
                    viewable
                    required
                />

                <flux:button type="submit" variant="primary" class="w-full cursor-pointer" data-test="register-button">
                    Create account
                </flux:button>
            </form>

            <p class="mt-5 text-sm text-zinc-400">
                Already have an account?
                <flux:link href="{{ route('login') }}" class="text-cyan-200">Sign in</flux:link>.
            </p>
        </div>
    </section>
@endsection
