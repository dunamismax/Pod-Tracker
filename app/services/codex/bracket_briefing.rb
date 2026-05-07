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
    POWER_BAND_VERSION = "axes-v2".freeze

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

    # Deep per-axis playbook. Each axis gets the question being asked, the
    # 0-10 anchor bands, what to count and weight, common scoring pitfalls,
    # and the shape of evidence the LLM should cite. The axes are 0-10
    # and are NOT bracket-relative — a Bracket 2 deck and a Bracket 4 deck
    # share the same scale so a 7 means roughly the same thing across decks.
    AXES = [
      {
        "key" => "power",
        "label" => "Power",
        "question" => "If this deck sat down at a prepared table of similar-bracket decks, how often does it win?",
        "definition" => "Ability to win against prepared Commander tables under reasonable play.",
        "anchors" => {
          "0-2" => "Theme deck or precon shell. Often loses to itself.",
          "3-4" => "Upgraded precon. Has a plan but limited efficiency.",
          "5-6" => "Tuned casual. Reliable closer over a long game.",
          "7-8" => "High-power non-cEDH. Wins under interaction; fast under permission.",
          "9-10" => "cEDH-tuned. Wins through tutors and protection on a normal sequence."
        },
        "evaluate" => [
          "Identify the primary win condition. Is it a single combo, a value engine, a combat plan, or an alternate win?",
          "Count tutors, redundancy on key pieces, and protection (counters, hexproof, indestructible, ward) for that win line.",
          "Weigh efficiency: how much mana and how many turns does it take to assemble the win?",
          "Consider the closing speed under typical interaction — does the deck still win when one piece is countered?",
          "Compare to the anchor bands; pick the band whose description fits, then nudge by quality of pieces."
        ],
        "pitfalls" => [
          "Do not score Power off the commander's printed reputation alone — read the supporting cards.",
          "Do not reward 'cute synergy' that the deck does not actually assemble reliably.",
          "Tribal/value decks can score high Power if redundancy is dense; do not under-score them just because they lack a combo."
        ],
        "evidence_examples" => [
          "Names the win line (e.g. 'Najeela + extra combat triggers + Druids' Repository') and 2+ tutors that find it.",
          "Cites mana value of the win turn (e.g. 'cast Najeela turn 4 with Sol Ring + Mana Vault').",
          "Cites the protection count (e.g. '6 free counterspells: Force of Will, Force of Negation, Pact of Negation, Fierce Guardianship...')."
        ]
      },
      {
        "key" => "speed",
        "label" => "Speed",
        "question" => "How early can this deck threaten lethal or a win-equivalent board state?",
        "definition" => "How quickly the deck threatens a win or a board state opponents must answer.",
        "anchors" => {
          "0-2" => "Plays fair Magic for many turns; closes turn 9+.",
          "3-4" => "Sets up through turn 5-6, closes turn 7-9.",
          "5-6" => "Stabilizes turn 4-5, can close on a big turn 6-7.",
          "7-8" => "Threatens lethal turns 4-6 with disruption available.",
          "9-10" => "Goldfishes turn 3-4 routinely."
        },
        "evaluate" => [
          "Goldfish the deck mentally: with an opening hand of 7 cards and average draws, when can it close?",
          "Count fast mana (Sol Ring, Mana Crypt, Mana Vault, the Moxen, Lotus Petal, Jeweled Lotus, Ancient Tomb, City of Traitors) and ritual effects.",
          "Count efficient tutors (1-2 mana tutors land here: Vampiric, Demonic, Imperial Seal, Mystical, Worldly, Enlightened, Grim Tutor).",
          "Identify whether the win line is a single big turn or a multi-turn assembly.",
          "Account for early-turn pressure even if the kill is later: a turn-2 Necropotence is fast even if the kill is turn 6."
        ],
        "pitfalls" => [
          "Speed is not Power — a fast all-in deck that loses to one counter is still fast.",
          "Ramp is not the same as fast mana. A turn-2 Cultivate is normal-pace, not fast.",
          "Do not score Speed by extra-turn count alone unless the deck actively chains them."
        ],
        "evidence_examples" => [
          "Cites the goldfish turn ('goldfishes turn 4 on opening Sol Ring + Mana Vault into Najeela + combat trigger').",
          "Cites the fast-mana suite count ('5 fast-mana sources: Sol Ring, Mana Crypt, Jeweled Lotus, Lotus Petal, Ancient Tomb').",
          "Cites the tutor density that compresses the kill ('Demonic Tutor + Vampiric Tutor + Imperial Seal grab the missing piece on turn 3')."
        ]
      },
      {
        "key" => "interaction",
        "label" => "Interaction",
        "question" => "How well does the deck answer threats and protect its plan?",
        "definition" => "Removal, counters, wipes, and protection density and quality.",
        "anchors" => {
          "0-2" => "Almost no interaction. Hopes opponents kill each other.",
          "3-4" => "Some removal at sorcery speed. Mostly reactive when forced.",
          "5-6" => "Balanced spot removal, a wipe or two, some protection.",
          "7-8" => "Dense, instant-speed answers. Plays defense well.",
          "9-10" => "Free counters, pinpoint removal, hate pieces — interaction-dense."
        },
        "evaluate" => [
          "Count instant-speed removal vs sorcery-speed. Instant beats sorcery for this axis.",
          "Count free or near-free interaction (Force of Will, Force of Negation, Fierce Guardianship, Pact of Negation, Deflecting Swat, Deadly Rollick, Mindbreak Trap).",
          "Count board wipes and graveyard hate (Bojuka Bog, Soul-Guide Lantern, etc.).",
          "Distinguish protection (Veil of Summer, Silence, Mana Drain on your own line) from offensive interaction.",
          "Density matters as much as quality: 6 counterspells is denser than 2 free ones."
        ],
        "pitfalls" => [
          "Tutors are not interaction.",
          "Card draw is not interaction unless it doubles as a counterspell (Brainstorm-into-Force is still card selection, not interaction).",
          "A single Cyclonic Rift does not make a deck interaction-dense."
        ],
        "evidence_examples" => [
          "Counts answer types: 'Spot removal: Swords to Plowshares, Path to Exile, Assassin's Trophy. Counters: Force of Will, Force of Negation, Mana Drain. Wipes: Toxic Deluge, Cyclonic Rift.'",
          "Calls out free interaction explicitly.",
          "Notes interaction asymmetry — a deck with 4 wipes but 0 counters plays differently than 4 counters and 0 wipes."
        ]
      },
      {
        "key" => "consistency",
        "label" => "Consistency",
        "question" => "How often does this deck execute its game plan game over game, not just on the curve?",
        "definition" => "How reliably the deck executes its game plan turn over turn.",
        "anchors" => {
          "0-2" => "Highly variable; depends on top-decks.",
          "3-4" => "Plan often shows up; sometimes whiffs entirely.",
          "5-6" => "Plan shows up most games. Curve and mana usually cooperate.",
          "7-8" => "Tutors and draw smooth out variance.",
          "9-10" => "Tutored mana base, redundant pieces, near-deterministic lines."
        },
        "evaluate" => [
          "Count tutors and the breadth of what they find (narrow tutor < broad tutor).",
          "Count card draw and selection. A deck with Rhystic Study + Mystic Remora + Sylvan Library digs reliably.",
          "Audit redundancy — how many copies of each role does the deck run? (e.g. how many ramp pieces, how many counterspells, how many win conditions).",
          "Audit the mana base. Fetch + dual lands beat tap-lands; mono-color and two-color decks generally land higher than 4-5 color without fetches.",
          "Account for color-screw risk in 4-5 color decks lacking a real fixed mana base."
        ],
        "pitfalls" => [
          "Do not conflate Consistency with Power. A precon can be consistent (it always does the same fair thing).",
          "Tribal decks with 30+ creature ramp/draw count higher than they look at first glance.",
          "Sub-100 decks or decks with obvious 'flex slots' usually land mid at best."
        ],
        "evidence_examples" => [
          "Counts tutors ('5 unconditional tutors: Demonic, Vampiric, Imperial Seal, Grim Tutor, Diabolic Intent').",
          "Counts redundancy ('11 ramp pieces, 9 card draw, 4 redundant combo finishers').",
          "Calls out mana-base quality ('original duals + fetches + Command Tower' or 'mostly tap-lands and Commander signets')."
        ]
      },
      {
        "key" => "salt",
        "label" => "Salt",
        "question" => "How likely is this deck to produce frustration at a typical Commander table? Neutral and descriptive — not a moral judgment about player intent.",
        "definition" => "Likelihood of producing frustration at a typical Commander table. Neutral, descriptive — not a moral judgment.",
        "anchors" => {
          "0-2" => "No common salt drivers.",
          "3-4" => "Occasional friction (theft, tax effects, splashy game-warp).",
          "5-6" => "Multiple salt drivers; opponents will likely groan.",
          "7-8" => "Stax, mass land denial, locks, or repetitive game-shapes.",
          "9-10" => "Will likely end games socially even when it doesn't end them mechanically."
        },
        "evaluate" => [
          "Count canonical salt drivers: stax pieces, mass land denial, extra-turn cards, theft (Bribery, Gilded Drake), chaos effects, repetitive locks (Winter Orb + Stasis), compact two-card combos.",
          "Weigh fast mana modestly — an isolated Sol Ring is normal; a full fast-mana suite at a casual table is salty.",
          "Weigh repetitive game shapes (Polymorph, Storm-into-win, Stax + win) higher than splashy big-turn decks.",
          "Weigh by frequency, not just presence: a deck with one extra-turn card at sorcery speed is mildly salty; a deck that chains them is high.",
          "Use neutral language: 'this card produces friction because <pattern>', not 'this player is mean'."
        ],
        "pitfalls" => [
          "Counterspells are NOT salt. Dense interaction is high Interaction, not high Salt, unless it leads to a soft lock.",
          "Salt is not Power. A fast non-salty combo deck (Tymna/Thrasios/Thoracle) wins without ending the social experience the way Stax does.",
          "Do not raise Salt for high Power alone — a Bracket 4 control deck need not be salty.",
          "Do not pile multiple salt drivers under one umbrella — Mass Land Denial, Extra Turns, and Stax are distinct patterns."
        ],
        "evidence_examples" => [
          "Names the salt drivers explicitly ('Mass land denial: Armageddon, Ravages of War. Extra turns: Time Warp, Temporal Manipulation. Stax: Winter Orb, Stasis, Static Orb.').",
          "Calls out the table experience ('once a lock lands, three opponents pass turns waiting to lose').",
          "Distinguishes fast non-salt combo (Thoracle) from salty grind (Stax)."
        ]
      },
      {
        "key" => "social_friction",
        "label" => "Social Friction",
        "question" => "How much Rule 0 conversation does this deck need before sitting down at a stranger's pod?",
        "definition" => "How much Rule 0 conversation a deck or pod needs before sitting down.",
        "anchors" => {
          "0-2" => "Plays clean. No surprise mechanics. Bracket reads at a glance.",
          "3-4" => "One specific element to flag (an extra turn, a splashy combo finisher).",
          "5-6" => "A few elements: combo line, salty interaction, or a near-bracket-line tilt.",
          "7-8" => "Strong upfront discussion needed: pubstomp risk, stax, repetitive lock.",
          "9-10" => "Pod won't be enjoyable without explicit pre-game alignment."
        },
        "evaluate" => [
          "Identify everything a polite player would mention at the start of a game: Game Changers, two-card combos, mass land denial, extra turns, stax, mill, theft, chaos.",
          "Audit bracket-line tension: a deck that almost qualifies for the next bracket up generates more Rule-0 discussion.",
          "Weigh combo opacity: a known and named combo line is lower friction than a hidden one (e.g. Thassa's Oracle + Demonic Consultation is well-known; an obscure infinite is more disclosure-heavy).",
          "Weigh expected game length and pace shifts ('this deck plays a long fair game then wins on a sudden turn' is friction).",
          "Friction is independent of Power — a Bracket 2 chaos deck can be high friction; a Bracket 4 fair midrange can be low friction."
        ],
        "pitfalls" => [
          "Do not equate Friction to Salt. Friction is about pre-game communication; Salt is about in-game experience.",
          "A clean cEDH combo deck can score Friction 4 if its plan is well-known and disclosed; it doesn't auto-9 because it's Bracket 5.",
          "Tribal aggressive decks usually have low Friction even at high Power."
        ],
        "evidence_examples" => [
          "Lists the specific disclosures the player should make ('disclose: Thassa's Oracle line, Demonic Consultation, fast-mana suite').",
          "Names the bracket-line tension ('one Game Changer away from Bracket 4 if Mana Vault gets cut').",
          "Notes pace shift ('plays fair through turn 5, kills on turn 6 with combo')."
        ]
      }
    ].freeze

    # Cross-axis principles the LLM must respect when scoring. These are
    # quality bar, not extra criteria — they enforce the difference
    # between axes the response often blurs.
    AXIS_INVARIANTS = [
      "All six axes use the SAME 0-10 scale for every bracket. A '7 Power' means roughly the same thing in a Bracket 2 deck as in a Bracket 4 deck — the Bracket 2 deck just rarely earns it.",
      "Power and Speed are different. Power asks 'does it win'; Speed asks 'when does it threaten lethal'. A slow control deck can be high Power, low Speed.",
      "Power and Consistency are different. Power asks 'how strong when assembled'; Consistency asks 'how often it shows up'. A glass-cannon combo can be high Power, mid Consistency.",
      "Salt and Social Friction are different. Salt is in-game experience; Social Friction is pre-game disclosure. Counterspells are not salt; chaos is not necessarily friction.",
      "Score axes against the absolute scale, then sub-band the bracket. Do NOT inflate axes to justify a bracket call you already made; let the axes be what they are.",
      "Empty-handed scoring is forbidden — every axis value must cite at least one specific card or pattern from the supplied decklist."
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
        "axis_invariants" => AXIS_INVARIANTS,
        "scoring_guidance" => scoring_guidance,
        "rules_authority" => rules_authority
      }
    end

    def self.scoring_guidance
      [
        "Treat Commander Brackets as the headline output. The bracket call must respect the published gates, not the deck's vibes.",
        "If the decklist meets the gates of multiple brackets, choose the highest bracket whose gates the deck still satisfies.",
        "Use sub_band low/mid/high to place the deck inside the bracket. 'low' = the deck barely qualifies for this bracket and could play down; 'mid' = it sits squarely in the band; 'high' = it pushes the upper edge and could pass for the next bracket on a tuned night.",
        "Sub-band is not the same as raw Power. A Bracket 3 deck can be 'high' because of combo compactness even if its Power is 6.",
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
