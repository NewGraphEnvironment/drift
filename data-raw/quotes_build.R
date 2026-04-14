# Build script for drift startup quotes.
#
# This script is the source of truth for the quote library.
# Run it to regenerate:
#   data-raw/quotes_audit.csv    (full provenance record — tracked, not shipped)
#   inst/extdata/quotes.csv      (shipped in the package, read by R/zzz.R on attach)
#
# To add, edit, or remove a quote: edit the `quotes` tibble below, then run:
#   Rscript data-raw/quotes_build.R
#
# Provenance requirement: every row must have a primary-source URL where the
# exact text was confirmed via WebFetch on the verification_date. If you add a
# new row without that, the audit breaks.

library(tibble)

quotes <- tribble(
  ~quote, ~author, ~source, ~source_type, ~source_outlet, ~verification_date,

  # --- Kendrick Lamar (6) ---
  "I'm not even the same person I was yesterday. That's what keeps me creative.",
  "Kendrick Lamar",
  "https://www.wmagazine.com/culture/kendrick-lamar-interview-2022",
  "interview", "W Magazine", "2026-04-14",

  "I have so much discipline as far as repetition—I don't give a fuck if it's a thousand push-ups or pull-ups or whatever, but it's always that extra 5 percent I'm like, What am I on today? What's going to be the evolution for myself today?",
  "Kendrick Lamar",
  "https://www.wmagazine.com/culture/kendrick-lamar-interview-2022",
  "interview", "W Magazine", "2026-04-14",

  "It's stuff that I've written that's just now seeing daylight, because I wasn't secure with myself in order to do it.",
  "Kendrick Lamar",
  "https://www.wmagazine.com/culture/kendrick-lamar-interview-2022",
  "interview", "W Magazine", "2026-04-14",

  "It's not me pointing at my community; it's me pointing at myself.",
  "Kendrick Lamar",
  "https://www.npr.org/2015/12/29/461129966/kendrick-lamar-i-cant-change-the-world-until-i-change-myself-first",
  "interview", "NPR", "2026-04-14",

  "You can have the platinum album, but when you still feel like you haven't quite found your place in the world...",
  "Kendrick Lamar",
  "https://www.npr.org/2015/12/29/461129966/kendrick-lamar-i-cant-change-the-world-until-i-change-myself-first",
  "interview", "NPR", "2026-04-14",

  "It's not only caging us in the prisons, but up here as well.",
  "Kendrick Lamar",
  "https://www.vice.com/en/article/deeper-than-just-the-music-kendrick-lamars-extended-noisey-bompton-interview/",
  "interview", "Noisey/VICE", "2026-04-14",

  # --- Anderson .Paak (3) ---
  "I always thought it was cool to be able to go in any room and put that shit in. There's no ceilings, no boundaries; it's free.",
  "Anderson .Paak",
  "https://www.interviewmagazine.com/music/anderson-paak",
  "interview", "Interview Magazine", "2026-04-14",

  "The joy and the pain — you just need both.",
  "Anderson .Paak",
  "https://www.thegentlemansjournal.com/article/anderson-paak-interview-2024/",
  "interview", "The Gentleman's Journal", "2026-04-14",

  "Sometimes you have to laugh in order not to cry.",
  "Anderson .Paak",
  "https://www.thegentlemansjournal.com/article/anderson-paak-interview-2024/",
  "interview", "The Gentleman's Journal", "2026-04-14",

  # --- Bad Bunny (5) ---
  "What's the point in being here? To show the world who I am.",
  "Bad Bunny",
  "https://www.rollingstone.com/music/music-features/bad-bunny-puerto-rico-new-album-acting-interview-1235227338/",
  "interview", "Rolling Stone", "2026-04-14",

  "I'll die and that's it — I'm not going to take anything with me.",
  "Bad Bunny",
  "https://www.rollingstone.com/music/music-features/bad-bunny-puerto-rico-new-album-acting-interview-1235227338/",
  "interview", "Rolling Stone", "2026-04-14",

  "When you're far away, you appreciate things more and you understand them better.",
  "Bad Bunny",
  "https://www.rollingstone.com/music/music-features/bad-bunny-puerto-rico-new-album-acting-interview-1235227338/",
  "interview", "Rolling Stone", "2026-04-14",

  "If I have the chance to say something, I will say it — but that doesn't obligate me to always say something.",
  "Bad Bunny",
  "https://www.gq.com/story/bad-bunny-good-times-profile",
  "interview", "GQ", "2026-04-14",

  "Never stop dreaming and being yourselves; never forget where you come from. There are many ways to serve your country; we chose music.",
  "Bad Bunny",
  "https://www.grammy.com/news/bad-bunny-if-i-have-chance-say-something-i-will-say-it",
  "speech", "Latin Grammys 2025", "2026-04-14",

  # --- Young Thug (3) ---
  "Let people know that I'm not just a rapper, I'm a human being. Those are the things that make people grow. People that want to commit suicide, you might give them another chance.",
  "Young Thug",
  "https://www.thefader.com/2019/08/21/young-thug-fader-cover-quotes",
  "interview", "The FADER", "2026-04-14",

  "Anything in the world got style. A roach got style, the way he run, the way he hide, the way he eat. Everything has style, so I don't care to look for that.",
  "Young Thug",
  "https://www.thefader.com/2019/08/21/young-thug-fader-cover-quotes",
  "interview", "The FADER", "2026-04-14",

  "You can't learn how to keep inventing. You just keep learning how to keep learning. What's in you is in you.",
  "Young Thug",
  "https://www.rollingstone.com/music/music-features/young-thug-punk-ysl-1202951/",
  "interview", "Rolling Stone", "2026-04-14",

  # --- Travis Scott (4) ---
  "I'm trying to have something here that's like an experience that's passed on to generations.",
  "Travis Scott",
  "https://www.rollingstone.com/music/music-features/travis-scott-utopia-fatherhood-next-album-1235500436/",
  "interview", "Rolling Stone", "2026-04-14",

  "Can't afford shit. And my mom's disabled. And still she looked after me. That's why I move the way I move. Nothing stopping me, bro.",
  "Travis Scott",
  "https://www.rollingstone.com/music/music-features/travis-scott-rap-superstar-cover-story-767906/",
  "interview", "Rolling Stone", "2026-04-14",

  "Everybody go through shit. He still a dope musician.",
  "Travis Scott",
  "https://www.rollingstone.com/music/music-features/travis-scott-rap-superstar-cover-story-767906/",
  "interview", "Rolling Stone", "2026-04-14",

  "People wanted to keep rap a certain way. I didn't.",
  "Travis Scott",
  "https://www.rollingstone.com/music/music-features/travis-scott-utopia-fatherhood-next-album-1235500436/",
  "interview", "Rolling Stone", "2026-04-14",

  # --- Future (5) ---
  "I embraced what I thought people was gonna hate about me. I was gonna turn the hate into love.",
  "Future",
  "https://www.rollingstone.com/music/music-news/future-syrup-strippers-and-heavy-angst-with-the-superstar-mc-113132/9/",
  "interview", "Rolling Stone", "2026-04-14",

  "I was born Nayvadius, but now I'm Future. Should I dwell on what Nayvadius was supposed to be?",
  "Future",
  "https://www.rollingstone.com/music/music-news/future-syrup-strippers-and-heavy-angst-with-the-superstar-mc-113132/9/",
  "interview", "Rolling Stone", "2026-04-14",

  "Don't ask for a million dollars. Ask for the stuff that'll get you a million dollars — your health, your brain, your sanity, wisdom.",
  "Future",
  "https://www.rollingstone.com/music/music-news/future-syrup-strippers-and-heavy-angst-with-the-superstar-mc-113132/9/",
  "interview", "Rolling Stone", "2026-04-14",

  "I want to keep doing what I'm doing and see how far I can go. See when it stops. See what the end is like.",
  "Future",
  "https://www.rollingstone.com/music/music-news/future-syrup-strippers-and-heavy-angst-with-the-superstar-mc-113132/9/",
  "interview", "Rolling Stone", "2026-04-14",

  "I think I need to be a vessel of what not to do. In some things, I need to be a lesson on what to do.",
  "Future",
  "https://www.billboard.com/music/features/future-2022-interview-cover-story-1235171775/",
  "interview", "Billboard", "2026-04-14",

  # --- Metro Boomin (4) ---
  "More than any accolades, sales and everything, I just want people to know at the end that I cared the whole time. I cared a lot.",
  "Metro Boomin",
  "https://www.complex.com/music/a/j-mckinney/metro-boomin-symphonic-interview",
  "interview", "Complex", "2026-04-14",

  "It's not about, 'Oh, look at me like a star!' Look at me like I care.",
  "Metro Boomin",
  "https://www.billboard.com/music/features/metro-boomin-spider-verse-producer-interview-cover-story-1235430134/",
  "interview", "Billboard", "2026-04-14",

  "The amount of grind and effort I put in my 20s into the music, I'mma put into the business aspect through these 30s. I watched my music seeds grow from 20 to 30. I can watch the rest of these grow from 30 to 40.",
  "Metro Boomin",
  "https://www.billboard.com/music/features/metro-boomin-spider-verse-producer-interview-cover-story-1235430134/",
  "interview", "Billboard", "2026-04-14",

  "I can't really identify if I ever really felt that I made it. Because even though we got a good start, we came a long way... it's a way even longer to go.",
  "Metro Boomin",
  "https://www.highsnobiety.com/p/metro-boomin-interview/",
  "interview", "Highsnobiety", "2026-04-14",

  # --- Playboi Carti (4) ---
  "I just be rapping. Every day I discover something new about myself, and I just do it.",
  "Playboi Carti",
  "https://www.thefader.com/2019/06/12/playboi-carti-cover-story",
  "interview", "The FADER", "2026-04-14",

  "Some people don't know how to be alone, but I love it.",
  "Playboi Carti",
  "https://www.rollingstone.com/music/music-features/playboi-carti-profile-1142354/",
  "interview", "Rolling Stone", "2026-04-14",

  "That's just part of creating something new. If this is something that people accept right away, how different is it?",
  "Playboi Carti",
  "https://www.rollingstone.com/music/music-features/playboi-carti-profile-1142354/",
  "interview", "Rolling Stone", "2026-04-14",

  "I've been like this my whole life. When I do speak, it's for a reason.",
  "Playboi Carti",
  "https://www.rollingstone.com/music/music-features/playboi-carti-profile-1142354/",
  "interview", "Rolling Stone", "2026-04-14",

  # --- Ty Dolla $ign (3) ---
  "Instruments last forever. When you listen to a computer sound, those become of a time.",
  "Ty Dolla $ign",
  "https://www.interviewmagazine.com/music/ty-dolla-sign-hedonist-interview",
  "interview", "Interview Magazine", "2026-04-14",

  "When it comes to music, people have already played every single line — there's just different ways you can do it.",
  "Ty Dolla $ign",
  "https://www.billboard.com/music/rb-hip-hop/ty-dolla-sign-vulture-kanye-west-billboard-cover-1235712980/",
  "interview", "Billboard", "2026-04-14",

  "There's so many other artists out there, and now there's the internet and we can choose what we want, you don't have to be anything, you can just be yourself.",
  "Ty Dolla $ign",
  "https://www.interviewmagazine.com/music/ty-dolla-sign-hedonist-interview",
  "interview", "Interview Magazine", "2026-04-14",

  # --- Yeat (4) ---
  "If I just made 'Monëy So Big' 50 times in a row, I would be going nowhere.",
  "Yeat",
  "https://www.complex.com/music/a/eric-skelton/yeat-pray-love",
  "interview", "Complex", "2026-04-14",

  "It could feel very personal, but then four bars later I'm shit talking. It's like your life, everything's back and forth.",
  "Yeat",
  "https://www.thefader.com/2024/10/17/yeat-lyfestyle-album-synthetic-producer-interview",
  "interview", "The FADER", "2026-04-14",

  "If you sit there listening to other rappers all day, you start to sound like them, even subconsciously.",
  "Yeat",
  "https://magazine.032c.com/magazine/yeat-american-truths",
  "interview", "032c Magazine", "2026-04-14",

  "I believe that if I believe something, it will for sure happen. But you also can't fiend for anything.",
  "Yeat",
  "https://magazine.032c.com/magazine/yeat-american-truths",
  "interview", "032c Magazine", "2026-04-14",

  # --- Takeoff (3) ---
  "It's time to give me my flowers. I don't want them when I ain't here.",
  "Takeoff",
  "https://www.rollingstone.com/music/music-news/takeoff-death-final-interview-time-to-give-me-my-flowers-1234622507/",
  "interview", "Rolling Stone (Drink Champs)", "2026-04-14",

  "Kobe was in that gym when nobody was in that gym. You wasn't in that gym with me, and you wasn't in that basement with me, and we stayed cooking up that whole time, perfecting our craft and sharpening our tools.",
  "Takeoff",
  "https://www.billboard.com/music/rb-hip-hop/quavo-takeoff-built-for-infinity-links-jack-harlow-1235155418/",
  "interview", "Billboard", "2026-04-14",

  "All this is just material. I could give everything up for my grandma. That was the backbone of the family.",
  "Takeoff",
  "https://www.billboard.com/music/rb-hip-hop/quavo-takeoff-built-for-infinity-links-jack-harlow-1235155418/",
  "interview", "Billboard", "2026-04-14",

  # --- Offset (2) ---
  "It's feeling confident I'm going to go up with the music, but I'm down every day. It's the challenge of trying to be the best at your worst times.",
  "Offset",
  "https://globalgrind.com/6200560/set-gq-interview/",
  "interview", "GQ (via Global Grind)", "2026-04-14",

  "I get through my day thinking it's fake.",
  "Offset",
  "https://www.rollingstone.com/music/music-news/migos-offset-grieves-takeoff-through-music-art-1234741116/",
  "interview", "Rolling Stone", "2026-04-14",

  # --- Mike WiLL Made-It (4) ---
  "You gotta put your own identity on it.",
  "Mike WiLL Made-It",
  "https://www.rollingstone.com/music/music-features/mike-will-made-it-producer-interview-1234778846/",
  "interview", "Rolling Stone", "2026-04-14",

  "You got two different types of creatives. You got innovators and you got duplicators.",
  "Mike WiLL Made-It",
  "https://www.rollingstone.com/music/music-features/mike-will-made-it-producer-interview-1234778846/",
  "interview", "Rolling Stone", "2026-04-14",

  "Speak from your heart, speak from your soul. Express yourself.",
  "Mike WiLL Made-It",
  "https://www.rollingstone.com/music/music-features/mike-will-made-it-producer-interview-1234778846/",
  "interview", "Rolling Stone", "2026-04-14",

  "You can't create an AI me.",
  "Mike WiLL Made-It",
  "https://www.rollingstone.com/music/music-features/mike-will-made-it-producer-interview-1234778846/",
  "interview", "Rolling Stone", "2026-04-14",

  # --- Statik Selektah (5) ---
  "We could either fall back and fade away or bring it to another level.",
  "Statik Selektah",
  "https://djbooth.net/features/2020-10-27-statik-selektah-interview-audiomack-producer-success-tips/",
  "interview", "DJBooth/Audiomack", "2026-04-14",

  "I do a lot of things that I could do a different way and make a whole lot more money, but it doesn't feel right.",
  "Statik Selektah",
  "https://djbooth.net/features/2020-10-27-statik-selektah-interview-audiomack-producer-success-tips/",
  "interview", "DJBooth/Audiomack", "2026-04-14",

  "I'm just holding that torch and keeping it going, keeping the fundamentals of hip-hop alive.",
  "Statik Selektah",
  "https://djbooth.net/features/2020-10-27-statik-selektah-interview-audiomack-producer-success-tips/",
  "interview", "DJBooth/Audiomack", "2026-04-14",

  "Hip-Hop should be protected because it's not a novelty; it's a way of life.",
  "Statik Selektah",
  "https://ambrosiaforheads.com/2020/12/statik-selektah-protect-hip-hop/",
  "interview", "Ambrosia For Heads", "2026-04-14",

  "Education is everything for the next generation to understand what Hip-Hop actually is.",
  "Statik Selektah",
  "https://ambrosiaforheads.com/2020/12/statik-selektah-protect-hip-hop/",
  "interview", "Ambrosia For Heads", "2026-04-14",

  # --- YoungBoy Never Broke Again (6) ---
  "I am very curious of the person who I shall become.",
  "YoungBoy Never Broke Again",
  "https://www.billboard.com/music/features/youngboy-never-broke-again-cover-story-interview-1235208827/",
  "interview", "Billboard", "2026-04-14",

  "I will not be provoked, I will not be broken, and I'm not going back.",
  "YoungBoy Never Broke Again",
  "https://www.billboard.com/music/features/youngboy-never-broke-again-cover-story-interview-1235208827/",
  "interview", "Billboard", "2026-04-14",

  "The lifestyle is just a big distraction from your real purpose.",
  "YoungBoy Never Broke Again",
  "https://www.billboard.com/music/features/youngboy-never-broke-again-cover-story-interview-1235208827/",
  "interview", "Billboard", "2026-04-14",

  "Nighttime, when everybody's asleep — it's the most peaceful time ever inside of life to me.",
  "YoungBoy Never Broke Again",
  "https://www.billboard.com/music/features/youngboy-never-broke-again-cover-story-interview-1235208827/",
  "interview", "Billboard", "2026-04-14",

  "I think about how many lives I actually am responsible for when it comes to my music.",
  "YoungBoy Never Broke Again",
  "https://www.complex.com/music/a/tracewilliamcowen/youngboy-never-broke-again-rare-mormonism-prolific-release-strategy-music-impact-interview",
  "interview", "Complex", "2026-04-14",

  "I wish I knew when I was younger how unhealthy this was for me. Whatever type of energy I had inside me, I would've pushed it toward something else.",
  "YoungBoy Never Broke Again",
  "https://www.complex.com/music/a/tracewilliamcowen/youngboy-never-broke-again-rare-mormonism-prolific-release-strategy-music-impact-interview",
  "interview", "Complex", "2026-04-14",

  # === Domain-expert round (2026-04-14) ===
  # Floodplain/river process, Indigenous stewardship, ecosystem valuation, legacy conservation.
  # Tim Beechie included on the people list but yielded zero public interview material — process-paper-only voice.

  # --- David Montgomery (5) ---
  "One of the cool things about this profession is that you've got the freedom to follow a thread and see where it leads you.",
  "David Montgomery",
  "https://environment.uw.edu/news/2024/06/s2-e5-david-montgomery-and-soil-health/",
  "interview", "UW College of the Environment podcast", "2026-04-14",

  "We can restore soil actually fast in decades. It doesn't take centuries. It could be done on policy relevant timescales.",
  "David Montgomery",
  "https://environment.uw.edu/news/2024/06/s2-e5-david-montgomery-and-soil-health/",
  "interview", "UW College of the Environment podcast", "2026-04-14",

  "Civilizations that don't take care of their soil don't last.",
  "David Montgomery",
  "https://www.renewablematter.eu/en/david-r-montgomery-to-go-forward-we-must-look-down",
  "interview", "Renewable Matter", "2026-04-14",

  "There's no waste in Nature. Everything becomes something else. Circular economy is Nature's economy.",
  "David Montgomery",
  "https://www.renewablematter.eu/en/david-r-montgomery-to-go-forward-we-must-look-down",
  "interview", "Renewable Matter", "2026-04-14",

  "Soil degradation plays out in a time frame way longer than most people pay attention to. It's invisible to the naked eye.",
  "David Montgomery",
  "https://www.renewablematter.eu/en/david-r-montgomery-to-go-forward-we-must-look-down",
  "interview", "Renewable Matter", "2026-04-14",

  # --- Ellen Wohl (4) ---
  "Our rivers should not all look the same. I'd like to celebrate river diversity, and have people think about why a river appears as it does and what processes underlie that appearance.",
  "Ellen Wohl",
  "https://www.biohabitats.com/newsletter/wood-as-a-tool-in-stream-and-river-restoration/expert-qa-dr-ellen-wohl/",
  "interview", "Biohabitats Leaf Litter", "2026-04-14",

  "People often think that a messy river, one with downed trees, beaver dams, and all kinds of brush in them are bad, but in fact they are the healthiest kind of river.",
  "Ellen Wohl",
  "https://owutranscript.com/2014/10/06/snc-wohl/",
  "lecture", "Ohio Wesleyan University lecture coverage", "2026-04-14",

  "That's a big component of the fun of research: you start on one path, but never know exactly where it will take you.",
  "Ellen Wohl",
  "https://www.biohabitats.com/newsletter/wood-as-a-tool-in-stream-and-river-restoration/expert-qa-dr-ellen-wohl/",
  "interview", "Biohabitats Leaf Litter", "2026-04-14",

  "I'd prefer taking a less controlling approach, where you allow the structure to evolve and don't fasten everything in.",
  "Ellen Wohl",
  "https://www.biohabitats.com/newsletter/wood-as-a-tool-in-stream-and-river-restoration/expert-qa-dr-ellen-wohl/",
  "interview", "Biohabitats Leaf Litter", "2026-04-14",

  # --- Robin Wall Kimmerer (4) ---
  "Paying attention is a form of reciprocity with the living world, receiving the gifts with open eyes and open heart.",
  "Robin Wall Kimmerer",
  "https://www.litcharts.com/lit/braiding-sweetgrass/quotes",
  "book", "Braiding Sweetgrass (2013)", "2026-04-14",

  "In some Native languages the term for plants translates to 'those who take care of us.'",
  "Robin Wall Kimmerer",
  "https://www.goodreads.com/work/quotes/24362458-braiding-sweetgrass",
  "book", "Braiding Sweetgrass (2013)", "2026-04-14",

  "The currency in a gift economy is relationship, which is expressed as gratitude, as interdependence and the ongoing cycles of reciprocity.",
  "Robin Wall Kimmerer",
  "https://emergencemagazine.org/essay/the-serviceberry/",
  "essay", "Emergence Magazine", "2026-04-14",

  "Science polishes the gift of seeing; Indigenous traditions work with gifts of listening and language.",
  "Robin Wall Kimmerer",
  "https://onbeing.org/programs/robin-wall-kimmerer-the-intelligence-of-plants-2022/",
  "interview", "On Being with Krista Tippett", "2026-04-14",

  # --- Kyle Whyte (3) ---
  "I don't hope for a better climate future. Instead, I'm adamant that I will do whatever I can to build consensuality, to build trust, to build reciprocity with other people.",
  "Kyle Whyte",
  "https://forthewild.world/podcast-transcripts/dr-kyle-whyte-on-the-colonial-genesis-of-climate-change-295",
  "interview", "For The Wild podcast", "2026-04-14",

  "It's not going to take a year, two years, 10 years, 20 — that's the duration of time as measured through kinship.",
  "Kyle Whyte",
  "https://forthewild.world/podcast-transcripts/dr-kyle-whyte-on-the-colonial-genesis-of-climate-change-295",
  "interview", "For The Wild podcast", "2026-04-14",

  "Our sciences are based on the idea that we need to have a good understanding of what it means to be a people who can respond to a constantly changing environment.",
  "Kyle Whyte",
  "https://forthewild.world/podcast-transcripts/dr-kyle-whyte-on-the-colonial-genesis-of-climate-change-295",
  "interview", "For The Wild podcast", "2026-04-14",

  # --- Nancy Turner (4) ---
  "Recognition, respect, reciprocity, revitalization and renewal are what we all need to be a part of.",
  "Nancy Turner",
  "https://www.yammagazine.com/the-knowledge-keeper/",
  "interview", "YAM Magazine", "2026-04-14",

  "It's really important to develop a partnership, not integrate the knowledge, because they're different knowledge systems, but to listen to people who are living on the land.",
  "Nancy Turner",
  "https://www.yammagazine.com/the-knowledge-keeper/",
  "interview", "YAM Magazine", "2026-04-14",

  "You white people ask too many questions. I can hear Margaret Siwallace say that. Just listen. Just listen.",
  "Nancy Turner",
  "https://www.yammagazine.com/the-knowledge-keeper/",
  "interview", "YAM Magazine (recounting Nuxalk Elder Margaret Siwallace)", "2026-04-14",

  "I think that's a responsibility for anyone like myself who has had the privilege of being able to learn this knowledge to make sure that other people understand how important it is.",
  "Nancy Turner",
  "https://www.yammagazine.com/the-knowledge-keeper/",
  "interview", "YAM Magazine", "2026-04-14",

  # --- Jeannette Armstrong (3) ---
  "Science is a baby knowledge compared to our knowledge of the 12,000 years we've spent here on this land developing our understanding of how we as a people need to interact with each other.",
  "Jeannette Armstrong",
  "https://www.scienceworld.ca/stories/land-remembers-how-are-we-related-to-water/",
  "interview", "Science World / Land Remembers", "2026-04-14",

  "This water is sacred, nothing on this earth could live without this water no matter how big or small.",
  "Jeannette Armstrong",
  "https://www.scienceworld.ca/stories/land-remembers-how-are-we-related-to-water/",
  "interview", "Science World (recalling her grandmother)", "2026-04-14",

  "We give our bodies back to the land in a very physical way but we also do other things to the land. We can destroy it, or we can love the land and it can love us back.",
  "Jeannette Armstrong",
  "https://rpickard01.github.io/oral-histories-pocket-desert/pages/section-3-syilx-okanagan-relationships-to-the-land.html",
  "interview", "UBC Okanagan oral histories", "2026-04-14",

  # --- Kai Chan (5) ---
  "I strive to understand how social-ecological systems can be transformed to be both better and wilder.",
  "Kai Chan",
  "https://chanslab.ires.ubc.ca/people/chan/",
  "interview", "UBC CHANS Lab", "2026-04-14",

  "Our responsibilities to current and future persons and the natural world call for us all to be social and environmental advocates and activists.",
  "Kai Chan",
  "https://chanslab.ires.ubc.ca/people/chan/",
  "interview", "UBC CHANS Lab", "2026-04-14",

  "In the jobs-versus-environment debate, neither side is wrong. The problem is the 20th-century economy that forces us to choose.",
  "Kai Chan",
  "https://ires.ubc.ca/commentary-may-22-is-international-biodiversity-day-and-this-scientist-thinks-change-is-possible-op-ed-by-kai-chan-ires-faculty-member/",
  "op-ed", "UBC IRES", "2026-04-14",

  "I find hope in the hope of others.",
  "Kai Chan",
  "https://broadview.org/climate-activism-optimism/",
  "interview", "Broadview Magazine", "2026-04-14",

  "We get stuck in this place of thinking that it's our responsibility to be perfect, and once we've unlocked that, we should tell other people to do the same.",
  "Kai Chan",
  "https://broadview.org/climate-activism-optimism/",
  "interview", "Broadview Magazine", "2026-04-14",

  # --- David Suzuki (6) ---
  "We are the environment. Whatever we do to the environment, we do directly to ourselves.",
  "David Suzuki",
  "https://www.loe.org/shows/segments.html?programID=10-P13-00051&segmentID=6",
  "interview", "Living on Earth", "2026-04-14",

  "We have elevated the economy above the very things that keep us alive. And this is madness.",
  "David Suzuki",
  "https://www.loe.org/shows/segments.html?programID=10-P13-00051&segmentID=6",
  "interview", "Living on Earth", "2026-04-14",

  "What I've come to realize through Indigenous people and The Nature of Things is that what is driving us on a destructive path is our anthropocentric way of seeing the world.",
  "David Suzuki",
  "https://thenarwhal.ca/david-suzuki-the-nature-of-things/",
  "interview", "The Narwhal", "2026-04-14",

  "We see that we live as one small part of a web of relationships with animals and plants, with air, water, soil, sunlight.",
  "David Suzuki",
  "https://thenarwhal.ca/david-suzuki-the-nature-of-things/",
  "interview", "The Narwhal", "2026-04-14",

  "An understanding that everything is connected and what you do has consequences. That's the heart of environmentalism.",
  "David Suzuki",
  "https://thenarwhal.ca/david-suzuki-the-nature-of-things/",
  "interview", "The Narwhal", "2026-04-14",

  "When we cut some of the strands, we destroy the integrity of what allows us to be a part of it.",
  "David Suzuki",
  "https://thenarwhal.ca/david-suzuki-the-nature-of-things/",
  "interview", "The Narwhal", "2026-04-14",

  # --- Wade Davis (5) ---
  "Every language is an old-growth forest of the mind, a watershed, a thought, an ecosystem of spiritual possibilities.",
  "Wade Davis",
  "https://www.ted.com/talks/wade_davis_dreams_from_endangered_cultures",
  "speech", "TED Dreams from Endangered Cultures (2003)", "2026-04-14",

  "A language is a flash of the human spirit. It's a vehicle through which the soul of each particular culture comes into the material world.",
  "Wade Davis",
  "https://www.ted.com/talks/wade_davis_dreams_from_endangered_cultures",
  "speech", "TED Dreams from Endangered Cultures (2003)", "2026-04-14",

  "The ethnosphere is humanity's great legacy. It's the symbol of all that we are and all that we can be as an astonishingly inquisitive species.",
  "Wade Davis",
  "https://www.ted.com/talks/wade_davis_dreams_from_endangered_cultures",
  "speech", "TED Dreams from Endangered Cultures (2003)", "2026-04-14",

  "Every culture is a unique answer to a fundamental question: What does it mean to be human and alive?",
  "Wade Davis",
  "https://theeditionbroadsheet.com/issue/issue-6/wade-davis/",
  "interview", "The Edition Broadsheet", "2026-04-14",

  "The biggest curse of humanity has been cultural myopia, the idea that my world is the real world and everybody else is a failed attempt at being me.",
  "Wade Davis",
  "https://theeditionbroadsheet.com/issue/issue-6/wade-davis/",
  "interview", "The Edition Broadsheet", "2026-04-14",

  # --- Aldo Leopold (6) ---
  "One of the penalties of an ecological education is that one lives alone in a world of wounds.",
  "Aldo Leopold",
  "https://www.aldoleopold.org/blogs/the-foreword-that-was-not-to-be",
  "book", "Round River (1953), p. 165", "2026-04-14",

  "That land is a community is the basic concept of ecology, but that land is to be loved and respected is an extension of ethics.",
  "Aldo Leopold",
  "https://en.wikiquote.org/wiki/Aldo_Leopold",
  "book", "A Sand County Almanac (1949), Foreword", "2026-04-14",

  "We shall never achieve harmony with land, any more than we shall achieve absolute justice or liberty for people. In these higher aspirations the important thing is not to achieve, but to strive.",
  "Aldo Leopold",
  "https://www.litcharts.com/lit/a-sand-county-almanac/quotes",
  "book", "A Sand County Almanac (Oxford 1987), pp. 47-48", "2026-04-14",

  "To keep every cog and wheel is the first precaution of intelligent tinkering.",
  "Aldo Leopold",
  "https://www.litcharts.com/lit/a-sand-county-almanac/quotes",
  "book", "A Sand County Almanac, 'The Round River', p. 190", "2026-04-14",

  "Conservation is a state of harmony between men and land. Harmony with land is like harmony with a friend; you cannot cherish his right hand and chop off his left.",
  "Aldo Leopold",
  "https://www.litcharts.com/lit/a-sand-county-almanac/quotes",
  "essay", "A Sand County Almanac, 'The Ecological Conscience'", "2026-04-14",

  "Only the mountain has lived long enough to listen objectively to the howl of a wolf.",
  "Aldo Leopold",
  "https://www.sierraclub.org/sites/www.sierraclub.org/files/sce/rocky-mountain-chapter/Wolves-Resources/Thinking%20Like%20a%20Mountain%20-%20Aldo%20Leopold.pdf",
  "essay", "A Sand County Almanac, 'Thinking Like a Mountain'", "2026-04-14",

  # --- Wendell Berry (7) ---
  "Kindly use depends upon intimate knowledge, the most sensitive responsiveness and responsibility.",
  "Wendell Berry",
  "https://www.goodreads.com/work/quotes/1984458-the-unsettling-of-america-culture-and-agriculture",
  "book", "The Unsettling of America (1977), Ch. 3", "2026-04-14",

  "It is impossible to care for each other more or differently than we care for the earth.",
  "Wendell Berry",
  "https://en.wikiquote.org/wiki/Wendell_Berry",
  "book", "The Unsettling of America (1977), Ch. 7", "2026-04-14",

  "Do unto those downstream as you would have those upstream do unto you.",
  "Wendell Berry",
  "https://en.wikiquote.org/wiki/Wendell_Berry",
  "essay", "Citizenship Papers (2003), 'Watershed and Commonwealth'", "2026-04-14",

  "We have lived by the assumption that what was good for us would be good for the world. We have been wrong. We must change our lives, so that it will be possible to live by the contrary assumption that what is good for the world will be good for us.",
  "Wendell Berry",
  "https://en.wikiquote.org/wiki/Wendell_Berry",
  "essay", "The Long-Legged House (1969), 'A Native Hill'", "2026-04-14",

  "I see that the life of this place is always emerging beyond expectation or prediction or typicality, that it is unique, given to the world minute by minute, only once, never to be repeated. And this is when I see that this life is a miracle, absolutely worth having, absolutely worth saving.",
  "Wendell Berry",
  "https://www.goodreads.com/work/quotes/74220-life-is-a-miracle-an-essay-against-modern-superstition",
  "book", "Life Is a Miracle (2000)", "2026-04-14",

  "It is easy for me to imagine that the next great division of the world will be between people who wish to live as creatures and people who wish to live as machines.",
  "Wendell Berry",
  "https://www.goodreads.com/work/quotes/74220-life-is-a-miracle-an-essay-against-modern-superstition",
  "book", "Life Is a Miracle (2000)", "2026-04-14",

  "A community is the mental and spiritual condition of knowing that the place is shared.",
  "Wendell Berry",
  "https://en.wikiquote.org/wiki/Wendell_Berry",
  "essay", "The Long-Legged House (1969), 'The Loss of the Future'", "2026-04-14",
)

stopifnot(
  all(nchar(quotes$quote) > 0),
  all(nchar(quotes$author) > 0),
  all(grepl("^https?://", quotes$source)),
  !anyDuplicated(quotes$quote)
)

dir.create("inst/extdata", showWarnings = FALSE, recursive = TRUE)

utils::write.csv(
  quotes,
  file = "data-raw/quotes_audit.csv",
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

utils::write.csv(
  quotes[, c("quote", "author", "source")],
  file = "inst/extdata/quotes.csv",
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

message(sprintf("Wrote %d quotes to inst/extdata/quotes.csv and data-raw/quotes_audit.csv", nrow(quotes)))
