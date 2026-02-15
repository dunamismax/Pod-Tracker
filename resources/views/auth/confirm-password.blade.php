@extends('layouts.pod')

@section('content')
    <section class="mx-auto w-full max-w-xl">
        <div class="auth-panel">
            <p class="ui-kicker">Authentication</p>
            <flux:heading size="xl" class="mt-2 text-zinc-100">Confirm password</flux:heading>
            <flux:subheading class="mt-2 text-zinc-400">
                Re-enter your password to continue.
            </flux:subheading>

            <form method="POST" action="{{ route('password.confirm.store') }}" class="mt-6 space-y-4">
                @csrf

                <flux:input
                    name="password"
                    :label="__('Password')"
                    type="password"
                    autocomplete="current-password"
                    viewable
                    required
                />
                <flux:error name="password" />

                <flux:button type="submit" variant="primary" class="w-full cursor-pointer">
                    Confirm
                </flux:button>
            </form>
        </div>
    </section>
@endsection
