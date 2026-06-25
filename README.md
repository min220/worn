Worn readme · MD
# worn
 
An AI-powered digital closet for iOS.

[case study + demo →](https://drive.google.com/drive/folders/16Qr_dmPiDHTFROZ9yhs6WPilZeKETE2y?usp=sharing)
 
## the problem
 
The average person wears about 20% of their wardrobe regularly. Not because they don't like the rest — because they forget it exists. Existing closet apps treat this as a cataloging problem. They're databases of your clothes. But the real problem isn't that you lack a list. It's that you lack a prompt.
 
worn is built to fix that.
 
## what it does
 
You upload photos of your clothes. Claude's vision API auto-tags each item across six dimensions: category, color, formality, occasion, weather, and aesthetic. You then search your closet using natural language — "sorority formal warm night," "rainy day brunch," "frat party memorial weekend" — and worn returns pieces that fit the vibe, biased toward items you've worn least often.
 
That last part is the whole point. The app tracks how often you wear each item and when you last wore it. Over time it becomes a record of how your closet actually lives, not just what's in it.
 
## what's built
 
- Native iOS app in Swift, SwiftUI, and SwiftData
- Photo upload from photo library, camera, or Files
- AI tagging via Claude vision API — structured JSON across six tag dimensions
- Natural language vibe search with reasoning, prioritizing under-worn pieces
- Wear tracking with count and last-worn date per item
- Manual edit for when the AI gets something wrong
- Custom design system with typography and brand identity built around the worn logo
## stack
 
- iOS: Swift, SwiftUI, SwiftData
- AI: Anthropic Claude API (Sonnet) for vision tagging and vibe search
- Image processing: Apple Vision framework for background removal
- Architecture: local-first, API calls direct from device
## design principles
 
**Surface what's forgotten, not what's optimized.** Every ranking decision biases toward under-worn pieces. The default behavior always pushes toward something you've forgotten.
 
**The AI suggests pieces; the user builds outfits.** The AI narrows the search to a handful of vibe-appropriate options. The human picks.
 
**Tags should reflect how people actually think.** "Warm-night dinner date" is really event + weather + time-of-day. The tag schema is designed to match the language people use when getting dressed, not fashion industry taxonomies.
 
## context
 
Self-taught Swift project. I learned iOS development by building this, using Claude as a real-time tutor throughout. The architectural decisions, product scoping, prompt tuning, and data model are mine.
 
