<section class="mx-auto mt-12 w-full max-w-xl rounded-2xl border border-zinc-200 bg-white p-8 shadow-sm">
    <flux:heading size="xl">Sign in with email OTP</flux:heading>
    <flux:subheading class="mt-2">Enter your email and we will send a one-time code.</flux:subheading>

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

    <form wire:submit="sendCode" class="mt-6 space-y-4">
        <flux:input
            wire:model="email"
            :label="__('Email')"
            type="email"
            autocomplete="email"
            required
            placeholder="email@example.com"
        />

        @error('email')
            <flux:text class="text-sm !text-red-600">{{ $message }}</flux:text>
        @enderror

        <flux:button type="submit" variant="primary" class="cursor-pointer" data-test="send-otp-button">
            Send code
        </flux:button>

        <flux:text wire:loading wire:target="sendCode" variant="subtle" class="text-sm">Sending code...</flux:text>
    </form>

    <p class="mt-4 text-sm text-zinc-600">
        Already got a code?
        <flux:link href="{{ route('verify') }}">Verify it here</flux:link>.
    </p>
</section>
