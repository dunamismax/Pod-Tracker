@extends('layouts.pod')

@section('content')
    <section class="mx-auto w-full max-w-xl">
        <div class="auth-panel">
            <p class="ui-kicker">Authentication</p>
            <flux:heading size="xl" class="mt-2 text-zinc-100">Reset password</flux:heading>
            <flux:subheading class="mt-2 text-zinc-400">
                Set a new password for your account.
            </flux:subheading>

            <form method="POST" action="{{ route('password.update') }}" class="mt-6 space-y-4">
                @csrf

                <input type="hidden" name="token" value="{{ $request->route('token') }}">

                <flux:input
                    name="email"
                    :label="__('Email')"
                    type="email"
                    autocomplete="email"
                    :value="old('email', $request->email)"
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

                <flux:button type="submit" variant="primary" class="w-full cursor-pointer" data-test="reset-password-button">
                    Reset password
                </flux:button>
            </form>
        </div>
    </section>
@endsection
