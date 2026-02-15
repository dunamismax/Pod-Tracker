<section class="mx-auto mt-12 w-full max-w-xl rounded-2xl border border-zinc-200 bg-white p-8 shadow-sm">
    <flux:heading size="xl">Verify your sign-in code</flux:heading>
    <flux:subheading class="mt-2">Enter the 6-digit code we emailed to you.</flux:subheading>

    <form wire:submit="verify" class="mt-6 space-y-4">
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

        <flux:input
            wire:model="code"
            :label="__('Code')"
            type="text"
            inputmode="numeric"
            pattern="\d{6}"
            maxlength="6"
            required
            placeholder="123456"
        />

        @error('code')
            <flux:text class="text-sm !text-red-600">{{ $message }}</flux:text>
        @enderror

        <flux:button type="submit" variant="primary" class="cursor-pointer" data-test="verify-otp-button">
            Sign in
        </flux:button>

        <flux:text wire:loading wire:target="verify" variant="subtle" class="text-sm">Verifying...</flux:text>
    </form>

    <p class="mt-4 text-sm text-zinc-600">
        Need another code?
        <flux:link href="{{ route('login') }}">Request a new one</flux:link>.
    </p>
</section>
