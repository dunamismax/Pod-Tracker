<div class="grid gap-6 md:grid-cols-2">
    <section class="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm md:col-span-2">
        <flux:heading size="xl">Dashboard</flux:heading>
        <flux:subheading class="mt-2">
            Create pods, view your memberships, and track upcoming events.
        </flux:subheading>
    </section>

    <section class="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm">
        <flux:heading size="lg">Create a pod</flux:heading>

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

        <form wire:submit="createPod" class="mt-4 space-y-4">
            <flux:input
                wire:model="name"
                :label="__('Pod name')"
                type="text"
                required
                maxlength="120"
                placeholder="Friday Pod"
            />

            @error('name')
                <flux:text class="text-sm !text-red-600">{{ $message }}</flux:text>
            @enderror

            <flux:textarea
                wire:model="description"
                :label="__('Description')"
                rows="3"
                maxlength="500"
                placeholder="Casual commander table"
            />

            @error('description')
                <flux:text class="text-sm !text-red-600">{{ $message }}</flux:text>
            @enderror

            <flux:button type="submit" variant="primary" class="cursor-pointer" data-test="create-pod-button">
                Create pod
            </flux:button>

            <flux:text wire:loading wire:target="createPod" variant="subtle" class="text-sm">Creating pod...</flux:text>
        </form>
    </section>

    <section class="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm">
        <flux:heading size="lg">Your pods</flux:heading>

        @if ($pods->isEmpty())
            <flux:text variant="subtle" class="mt-3 text-sm">No pods yet. Create your first pod.</flux:text>
        @else
            <ul class="mt-3 space-y-3">
                @foreach ($pods as $pod)
                    <li wire:key="pod-{{ $pod->id }}" class="rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-2">
                        <flux:text class="text-sm font-semibold text-zinc-900">{{ $pod->name }}</flux:text>
                        @if ($pod->description)
                            <flux:text variant="subtle" class="text-sm">{{ $pod->description }}</flux:text>
                        @endif
                    </li>
                @endforeach
            </ul>
        @endif
    </section>

    <section class="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm md:col-span-2">
        <flux:heading size="lg">Upcoming events</flux:heading>

        @if ($events->isEmpty())
            <flux:text variant="subtle" class="mt-3 text-sm">No upcoming events.</flux:text>
        @else
            <ul class="mt-3 space-y-3">
                @foreach ($events as $event)
                    <li wire:key="event-{{ $event->id }}" class="rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-2">
                        <flux:text class="text-sm font-semibold text-zinc-900">{{ $event->title }}</flux:text>
                        <flux:text variant="subtle" class="text-sm">
                            {{ $event->pod?->name }} · {{ $event->scheduled_for?->format('M j, Y g:i A') }}
                        </flux:text>
                    </li>
                @endforeach
            </ul>
        @endif
    </section>
</div>
