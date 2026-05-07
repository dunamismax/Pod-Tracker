module Codex
  # Packages the long-form context an LLM needs to produce a bracket and
  # power-band call comparable to a careful Commander Brackets reviewer.
  # Lives in one place so both deck and pod prompts stay aligned with the
  # public bracket pages.
  #
  # Static rules text is encoded in Ruby rather than being read from view
  # partials so the prompt content is deterministic and reviewable in tests.
  # The Game Changers list and Commander banlist are loaded from the
  # canonical seed files so the AI is always shown the same data the
  # deterministic checks use.
  class BracketBriefing
    BRACKETS_VERSION = "2026-02-09".freeze
    POWER_BAND_VERSION = "axes-v1".freeze

    BRACKET_RULES = [
      {
        "value" => 1,
        "label" => "Exhibition",
        "tagline" => "Theme-first, story-driven decks. Showpieces, jank, casual jam.",
        "expected_min_turn" => nil,
        "expectations" => [
          "Decks built around a clear theme, gimmick, or visual identity. Strict deck-building rules are common.",
          "Players are here for the experience, not the win.",
          "Games meander; nobody is racing to close."
        ],
        "restrictions" => [
          "Zero Game Changers.",
          "No mass land denial.",
          "No extra-turn cards.",
          "No two-card game-ending combos.",
          "Power level often well below Bracket 2; theme dominates card choices."
        ],
        "right_for" => "Showcases, narrative decks, group-hug variants where 'fun' beats 'win'."
      },
      {
        "value" => 2,
        "label" => "Core",
        "tagline" => "Precon-class casual. The heart of casual Commander.",
        "expected_min_turn" => nil,
        "expectations" => [
          "Roughly average power. Comparable to a modern preconstructed deck or a lightly-upgraded one.",
          "Decks may have a clear plan but limited efficiency.",
          "Games are interactive but rarely surgical."
        ],
        "restrictions" => [
          "Zero Game Changers.",
          "No mass land denial.",
          "No chained or looped extra turns (a single splashy turn is fine).",
          "No two-card game-ending combos."
        ],
        "right_for" => "New players, precon nights, players who want a long game with swingy moments."
      },
      {
        "value" => 3,
        "label" => "Upgraded",
        "tagline" => "Tuned casual. Strong synergy, sharp interaction, a few Game Changers.",
        "expected_min_turn" => 6,
        "expectations" => [
          "Decks are powered up with strong synergy and high card quality.",
          "Game Changers may appear but in small numbers.",
          "Games last at least six turns before anyone is at risk of winning or losing.",
          "Win conditions can resolve in a single big turn after resources are built up."
        ],
        "restrictions" => [
          "Up to 3 Game Changers.",
          "No mass land denial.",
          "No chained or looped extra turns.",
          "No two-card game-ending combos before turn 6.",
          "Do not 'sandbag' an early combo to call the deck Bracket 3 — if it is built to find and execute the combo early, it belongs higher."
        ],
        "right_for" => "Most well-built casual Commander decks. The most common landing zone."
      },
      {
        "value" => 4,
        "label" => "Optimized",
        "tagline" => "High-power non-cEDH. Banned list only, every card pulling weight.",
        "expected_min_turn" => nil,
        "expectations" => [
          "Decks are tightly built and intentionally powerful, but not optimized for the cEDH metagame specifically.",
          "Any Game Changers count is permitted; multiple Game Changers are normal.",
          "Mass land denial, fast mana, efficient tutors, and powerful combos are all on the table.",
          "Players expect a serious game with real decisions even when the deck is winning."
        ],
        "restrictions" => [
          "Banned list only — anything legal is allowed.",
          "Any number of Game Changers.",
          "Mass land denial, extra turns, and two-card combos are all permitted.",
          "Decks targeting the cEDH metagame should report Bracket 5 instead."
        ],
        "right_for" => "High-power tables, players who tune aggressively but are not playing the cEDH metagame."
      },
      {
        "value" => 5,
        "label" => "cEDH",
        "tagline" => "Competitive Commander. Decks built around the cEDH metagame.",
        "expected_min_turn" => nil,
        "expectations" => [
          "Deck choice is metagame-driven. Stax, fast combo, control, and big-mana lines are all represented.",
          "Wins are precise, often turn-three to turn-five, and frequently through tutored two-card combos.",
          "Interaction is dense and free or near-free spells (Force of Will, Fierce Guardianship, Pact of Negation, etc.) are common.",
          "Mulligans are aggressive; mana bases are pristine."
        ],
        "restrictions" => [
          "Banned list only.",
          "Decks must be intentionally targeting the cEDH metagame.",
          "Casually-tuned 'just strong' decks belong in Bracket 4, not Bracket 5."
        ],
        "right_for" => "cEDH events and tables of like-minded competitive Commander players."
      }
    ].freeze

    # Deterministic axis rubric. Each axis is 0-10 with explicit anchor
    # bands so the LLM's output stays comparable across decks.
    AXES = [
      {
        "key" => "power",
        "label" => "Power",
        "definition" => "Ability to win against prepared Commander tables under reasonable play.",
        "anchors" => {
          "0-2" => "Theme deck or precon shell. Often loses to itself.",
          "3-4" => "Upgraded precon. Has a plan but limited efficiency.",
          "5-6" => "Tuned casual. Reliable closer over a long game.",
          "7-8" => "High-power non-cEDH. Wins under interaction; fast under permission.",
          "9-10" => "cEDH-tuned. Wins through tutors and protection on a normal sequence."
        }
      },
      {
        "key" => "speed",
        "label" => "Speed",
        "definition" => "How quickly the deck threatens a win or a board state opponents must answer.",
        "anchors" => {
          "0-2" => "Plays fair Magic for many turns; closes turn 9+.",
          "3-4" => "Sets up through turn 5-6, closes turn 7-9.",
          "5-6" => "Stabilizes turn 4-5, can close on a big turn 6-7.",
          "7-8" => "Threatens lethal turns 4-6 with disruption available.",
          "9-10" => "Goldfishes turn 3-4 routinely."
        }
      },
      {
        "key" => "interaction",
        "label" => "Interaction",
        "definition" => "Removal, counters, wipes, and protection density and quality.",
        "anchors" => {
          "0-2" => "Almost no interaction. Hopes opponents kill each other.",
          "3-4" => "Some removal at sorcery speed. Mostly reactive when forced.",
          "5-6" => "Balanced spot removal, a wipe or two, some protection.",
          "7-8" => "Dense, instant-speed answers. Plays defense well.",
          "9-10" => "Free counters, pinpoint removal, hate pieces — interaction-dense."
        }
      },
      {
        "key" => "consistency",
        "label" => "Consistency",
        "definition" => "How reliably the deck executes its game plan turn over turn.",
        "anchors" => {
          "0-2" => "Highly variable; depends on top-decks.",
          "3-4" => "Plan often shows up; sometimes whiffs entirely.",
          "5-6" => "Plan shows up most games. Curve and mana usually cooperate.",
          "7-8" => "Tutors and draw smooth out variance.",
          "9-10" => "Tutored mana base, redundant pieces, near-deterministic lines."
        }
      },
      {
        "key" => "salt",
        "label" => "Salt",
        "definition" => "Likelihood of producing frustration at a typical Commander table. Neutral, descriptive — not a moral judgment.",
        "anchors" => {
          "0-2" => "No common salt drivers.",
          "3-4" => "Occasional friction (theft, tax effects, splashy game-warp).",
          "5-6" => "Multiple salt drivers; opponents will likely groan.",
          "7-8" => "Stax, mass land denial, locks, or repetitive game-shapes.",
          "9-10" => "Will likely end games socially even when it doesn't end them mechanically."
        }
      },
      {
        "key" => "social_friction",
        "label" => "Social Friction",
        "definition" => "How much Rule 0 conversation a deck or pod needs before sitting down.",
        "anchors" => {
          "0-2" => "Plays clean. No surprise mechanics. Bracket reads at a glance.",
          "3-4" => "One specific element to flag (an extra turn, a splashy combo finisher).",
          "5-6" => "A few elements: combo line, salty interaction, or a near-bracket-line tilt.",
          "7-8" => "Strong upfront discussion needed: pubstomp risk, stax, repetitive lock.",
          "9-10" => "Pod won't be enjoyable without explicit pre-game alignment."
        }
      }
    ].freeze

    def self.payload
      {
        "version" => BRACKETS_VERSION,
        "power_band_version" => POWER_BAND_VERSION,
        "primary_axis" => "Commander Brackets (Wizards beta) place a deck on a 1-5 scale by intent and play pattern. Brackets are the headline. The six 0-10 axes sub-band the deck inside its bracket.",
        "brackets" => BRACKET_RULES,
        "game_changers" => game_changers_payload,
        "banlist" => banlist_payload,
        "axes" => AXES,
        "scoring_guidance" => scoring_guidance,
        "rules_authority" => rules_authority
      }
    end

    def self.scoring_guidance
      [
        "Treat Commander Brackets as the headline output. The bracket call must respect the published gates, not the deck's vibes.",
        "If the decklist meets the gates of multiple brackets, choose the highest bracket whose gates the deck still satisfies.",
        "Use sub_band low/mid/high to place the deck inside the bracket using the 0-10 power and speed axes.",
        "If the bracket would be Bracket 3 because of a two-card combo, but the deck cannot find the combo before turn 6 reliably, that is still Bracket 3. If it can, that is Bracket 4.",
        "Do not invent cards or claim a card is in the deck unless it appears in the supplied decklist.",
        "Cite the specific cards and patterns that drove the call in the evidence and restrictions output.",
        "Flag uncertainty in the uncertainty array rather than guessing — a thin sample is better than a confident wrong call."
      ].freeze
    end

    def self.rules_authority
      [
        "The Commander banlist is the rules authority for legality. Cards on this list make the deck illegal regardless of bracket.",
        "The Game Changers list is descriptive — it shapes brackets but does not ban anything. Brackets 1-2 expect zero, Bracket 3 allows up to three, Brackets 4-5 allow any number.",
        "Companions are not assigned in Commander. Lutri remains companion-only-banned; it is legal as a commander or 99 but cannot be assigned as a companion."
      ].freeze
    end

    def self.game_changers_payload
      data = load_seed("brackets/game_changers.json")
      {
        "version" => data["version"],
        "source" => data["source"],
        "notes" => data["notes"],
        "categories" => data["categories"],
        "cards" => Array(data["cards"])
      }
    end

    def self.banlist_payload
      data = load_seed("legality_snapshots/current.json")
      {
        "format" => data["format"],
        "source" => data["source"],
        "effective_on" => data["effective_on"],
        "banned_names" => Array(data["banned_names"])
      }
    end

    def self.load_seed(relative_path)
      JSON.parse(Rails.root.join("db/seeds/commander", relative_path).read)
    end
    private_class_method :load_seed
  end
end
