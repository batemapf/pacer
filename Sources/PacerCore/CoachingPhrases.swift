/// Short spoken cues, shuffled without repeats until each category is exhausted.
public struct CoachingPhrases {
    private var bags: [PaceEngine.Cue: [String]] = [:]
    private var last: [PaceEngine.Cue: String] = [:]

    public init() {}

    public mutating func next(for cue: PaceEngine.Cue) -> String {
        var bag = bags[cue] ?? []
        if bag.isEmpty {
            bag = Self.library[cue]!.shuffled()
            if bag.last == last[cue] { bag.swapAt(0, bag.count - 1) }
        }
        let phrase = bag.removeLast()
        bags[cue] = bag
        last[cue] = phrase
        return phrase
    }

    public static let library: [PaceEngine.Cue: [String]] = [
        .onTarget: [
            "Right on pace. Look at you, being all consistent.",
            "Nailed it. The pavement is impressed.",
            "Perfect pace. Very main character of you.",
            "That's the rhythm. Your legs read the assignment.",
            "On target. Suspiciously competent jogging.",
            "Lovely pace. Gold star, slightly sweaty edition.",
            "You're cruising. Keep this excellent nonsense going.",
            "Bang on target. Someone tell the imaginary crowd.",
            "Nice work. This is your victory lap pace.",
            "Steady and strong. The squirrels are taking notes.",
            "That's it. Metronome with sneakers.",
            "Pace perfection. No notes from the tiny coach.",
            "You're in the sweet spot. Sadly, not actual candy.",
            "Excellent rhythm. Ten out of ten foot noises.",
            "On pace. The spreadsheet would be delighted.",
            "Keep it here. You've found your groove.",
            "Beautifully steady. Practically a moving landmark.",
            "You understood the jogging assignment.",
            "Right where we want you. Stylishly sweaty.",
            "Target acquired. Legs doing leg things brilliantly.",
            "Yes! That's the pace. Quiet little fist bump.",
            "You're cooking. At a sensible jogging temperature.",
            "Smooth sailing. Except, you know, on land.",
            "This pace has excellent manners.",
            "Consistency looks good on you.",
            "Strong work. Your future self says thanks.",
            "The pace is pacing. Outstanding.",
            "Stay in this groove. It's a good groove.",
            "Right on time. Like a very sweaty Swiss watch.",
            "That'll do nicely. Imaginary confetti deployed.",
            "Keep rolling. You've got a lovely rhythm.",
            "On target. The tiny coach approves this message.",
            "Your feet have formed a successful committee.",
            "Great pace. Make room on the invisible trophy shelf.",
            "Steady as you go. You've got this dialed in.",
            "Nothing to fix. Enjoy being excellent for a minute.",
            "That's your pace. Wear it like a crown.",
            "Good rhythm. Even the imaginary drummer agrees.",
            "A very respectable amount of zoom.",
            "On pace. Please accept this invisible high five."
        ],
        .speedUp: [
            "Almost there. A tiny bit quicker, if comfortable.",
            "Just a little more pace. One notch of extra zoom.",
            "Close to target. Gently pick it up.",
            "A small speed up. No superhero transformation required.",
            "You're nearly there. Add a sprinkle of hustle.",
            "A touch quicker. Think jog, with a little jazz.",
            "Nudge the pace up. Tiny upgrade, same excellent you.",
            "Just outside target. A little more pep.",
            "Slightly quicker. The finish line isn't going anywhere.",
            "Almost in the groove. A little extra zip.",
            "Small speed up. We're tuning, not launching.",
            "A gentle pickup. One click on the imaginary dial.",
            "Nearly on pace. Give the legs a polite suggestion.",
            "Just a touch faster. Pocket-sized hustle.",
            "A little quicker. The target is right up ahead."
        ],
        .slowDown: [
            "Almost there. Ease off just a little.",
            "A touch slower. Save some sparkle for later.",
            "Gently settle back. You're just ahead of target.",
            "Small slow down. Let the imaginary turbo cool.",
            "Close to target. Take a little off the pace.",
            "Ease back a notch. This isn't a chase scene.",
            "A little slower. Keep the swagger, lose a little speed.",
            "Tiny pace adjustment. Less zoom, same you.",
            "Just above target. Let the pace relax.",
            "Settle a little. You've got plenty of road left.",
            "Ease off gently. The squirrels aren't racing you.",
            "A touch less speed. Nice and sustainable.",
            "Nearly in the groove. Let it come down a little.",
            "Small slow down. Dial it back, not all the way off.",
            "Just a little easier. Save the dramatic finish."
        ],
        .speedUpMore: [
            "You're well below target speed. Pick it up gradually, if comfortable.",
            "Time for more pace. Upgrade from scenic stroll to jogging mode.",
            "Let's work toward the target. A little more hustle, not a sprint.",
            "Speed up gradually. The imaginary coach has noticed the sightseeing.",
            "More pace when you're ready. Bring the jog back into jogging.",
            "You're off the target. Build the speed gently.",
            "Pick it up a bit. The pavement tour can continue at jogging speed.",
            "Let's add some pace. No need to go full cartoon roadrunner.",
            "Speed up toward your target. Start with a comfortable pickup.",
            "More forward motion. Your shoes are ready for their next scene.",
            "A bigger pickup is needed. Build into it gently.",
            "Let's find that target pace. Bring a little more bounce.",
            "You're running slower than planned. Add pace if it feels right.",
            "Time to pick up the pace. Sensible hustle, please.",
            "More pace, gradually. The tiny coach believes in your legs."
        ],
        .slowDownMore: [
            "You're well ahead of target. Ease back gradually.",
            "Slow down a bit. We ordered a jog, not a rocket launch.",
            "Take the pace down. Your imaginary rival can wait.",
            "Ease off the turbo. Let's find your target pace.",
            "You're going faster than planned. Settle into a gentler rhythm.",
            "Slow down toward the target. No getaway car to catch.",
            "Bring the speed down. Save that extra gear for another day.",
            "Ease back. Your shoes have briefly mistaken this for a race.",
            "A bigger slow down is needed. Make it gradual.",
            "Less speed, please. The imaginary paparazzi can keep up.",
            "Settle back toward the plan. A jog with fewer special effects.",
            "You're well above target speed. Dial the effort back.",
            "Slow down gently. We can admire your turbo later.",
            "Ease up. The target pace is behind this much zoom.",
            "Bring it down a gear. Sustainable swagger wins today."
        ]
    ]
}
