<div class="grid gap-6 lg:grid-cols-3">
    <section class="ui-panel lg:col-span-3">
        <p class="ui-kicker">Control Center</p>
        <div class="mt-4 flex flex-col gap-6 xl:flex-row xl:items-end xl:justify-between">
            <div>
                <flux:heading size="xl" class="text-zinc-100">Dashboard</flux:heading>
                <flux:subheading class="mt-2 text-zinc-400">
                    Create pods, manage memberships, and keep your next events visible at a glance.
                </flux:subheading>
            </div>
            <div class="grid grid-cols-2 gap-3 sm:min-w-[14rem]">
                <div class="ui-panel-soft">
                    <flux:text class="text-xs uppercase tracking-[0.14em] text-zinc-400">Pods</flux:text>
                    <flux:heading size="lg" class="mt-1 text-zinc-100">{{ $pods->count() }}</flux:heading>
                </div>
                <div class="ui-panel-soft">
                    <flux:text class="text-xs uppercase tracking-[0.14em] text-zinc-400">Events</flux:text>
                    <flux:heading size="lg" class="mt-1 text-zinc-100">{{ $events->count() }}</flux:heading>
                </div>
            </div>
        </div>
    </section>

    <section class="ui-panel lg:col-span-1">
        <p class="ui-kicker">Workspace</p>
        <flux:heading size="lg" class="mt-2 text-zinc-100">Create a pod</flux:heading>
        <flux:text class="ui-muted mt-2">Set up a new pod and automatically join as owner.</flux:text>

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

        <form wire:submit="createPod" class="mt-6 space-y-4">
            <flux:input
                wire:model="name"
                :label="__('Pod name')"
                type="text"
                required
                maxlength="120"
                placeholder="Friday Pod"
            />
            <flux:error name="name" />

            <flux:textarea
                wire:model="description"
                :label="__('Description')"
                rows="3"
                maxlength="500"
                placeholder="Casual commander table"
            />
            <flux:error name="description" />

            <flux:button type="submit" variant="primary" class="w-full cursor-pointer" data-test="create-pod-button">
                Create pod
            </flux:button>

            <flux:text wire:loading wire:target="createPod" class="text-sm text-zinc-400">Creating pod...</flux:text>
        </form>
    </section>

    <section class="ui-panel lg:col-span-2">
        <p class="ui-kicker">Membership</p>
        <flux:heading size="lg" class="mt-2 text-zinc-100">Your pods</flux:heading>

        @if ($pods->isEmpty())
            <flux:text class="mt-4 text-sm text-zinc-400">No pods yet. Create your first pod to get started.</flux:text>
        @else
            <ul class="mt-4 space-y-3">
                @foreach ($pods as $pod)
                    <li wire:key="pod-{{ $pod->id }}" class="ui-list-item">
                        <flux:text class="text-sm font-semibold text-zinc-100">{{ $pod->name }}</flux:text>
                        @if ($pod->description)
                            <flux:text class="mt-1 text-sm text-zinc-400">{{ $pod->description }}</flux:text>
                        @endif
                    </li>
                @endforeach
            </ul>
        @endif
    </section>

    <section class="ui-panel lg:col-span-3">
        <p class="ui-kicker">Schedule</p>
        <flux:heading size="lg" class="mt-2 text-zinc-100">Upcoming events</flux:heading>

        @if ($events->isEmpty())
            <flux:text class="mt-4 text-sm text-zinc-400">No upcoming events.</flux:text>
        @else
            <ul class="mt-4 grid gap-3 sm:grid-cols-2">
                @foreach ($events as $event)
                    <li wire:key="event-{{ $event->id }}" class="ui-list-item">
                        <flux:text class="text-sm font-semibold text-zinc-100">{{ $event->title }}</flux:text>
                        <flux:text class="mt-1 text-sm text-zinc-400">
                            {{ $event->pod?->name }} · {{ $event->scheduled_for?->format('M j, Y g:i A') }}
                        </flux:text>
                        @if ($event->location)
                            <flux:text class="mt-1 text-xs uppercase tracking-[0.12em] text-zinc-500">{{ $event->location }}</flux:text>
                        @endif
                    </li>
                @endforeach
            </ul>
        @endif
    </section>
</div>
