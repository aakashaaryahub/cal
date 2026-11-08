// Initial values for the database-driven app content and plans.
//
// These are only used to seed an empty database (and to add keys introduced
// by later versions). After that the database is the source of truth: edit
// through the admin API, not here.

// Plan IDs are also the Google Play product IDs. Yearly is kept but hidden:
// with per-minute call costs, a heavy yearly user can cost more than they pay.
const PLANS = [
  { id: 'daypass', title: 'Day Pass', amountPaise: 3900, days: 1, badge: null, sortOrder: 1, active: true },
  { id: 'weekly', title: 'Weekly', amountPaise: 14900, days: 7, badge: null, sortOrder: 2, active: true },
  { id: 'monthly', title: 'Monthly', amountPaise: 39900, days: 30, badge: 'MOST POPULAR', sortOrder: 3, active: true },
  { id: 'yearly', title: 'Yearly', amountPaise: 399900, days: 365, badge: null, sortOrder: 4, active: false },
];

// Bumped when a release changes plans or the content keys in REVISED_KEYS;
// the server then applies them once to an existing database.
const CONTENT_REVISION = 2;
const REVISED_KEYS = ['premium', 'genderOptions', 'matching', 'tips', 'callLimits'];

const CONTENT = {
  // Whether choosing who you talk to needs Premium. Off: everyone can pick any
  // gender for free and the app hides Premium. Switch it in the admin dashboard.
  premiumEnabled: false,

  // Minutes of calls a day (random and friend calls together); 0 = unlimited.
  // Days run midnight to midnight India time.
  callLimits: { freeMinutesPerDay: 15, premiumMinutesPerDay: 120 },

  // Shared from the app's Invite button. {code} becomes the user's invite code;
  // `link` (e.g. the Play Store page) is added on its own line when set.
  invite: {
    message: 'Talk to me on VoxLink 🎙️ Sign up with my invite code {code} and we\'ll be friends right away.',
    link: '',
  },

  intro: {
    title: 'Make a new friend\nin one tap',
    subtitle: 'Anonymous voice calls with real people around the world. No video, no pressure.',
    chips: ['🎧 HD voice', '🔒 Number stays private', '🔞 18+ only'],
    // Illustrative avatars orbiting the intro screen (not real users).
    avatars: [
      { name: 'Aanya', countryCode: 'IN' },
      { name: 'Lucas', countryCode: 'BR' },
      { name: 'Mei', countryCode: 'JP' },
      { name: 'Omar', countryCode: 'AE' },
      { name: 'Chloe', countryCode: 'FR' },
      { name: 'Jake', countryCode: 'US' },
    ],
  },

  tips: [
    { emoji: '💬', text: 'Say hi first, most people are just as nervous as you.' },
    { emoji: '🛡️', text: 'Never share your number or address. Report anyone who makes you uncomfortable.' },
    { emoji: '⏭️', text: 'Not vibing? Tap Next to meet someone new instantly.' },
    { emoji: '💞', text: 'Liked talking to someone? Follow them. If they follow back, you can chat and call.' },
    // `premium: true` tips only show while Premium is switched on.
    { emoji: '👑', text: 'Premium gives you {premiumMinutes} minutes of calls a day and lets you choose female or male.', premium: true },
    { emoji: '🎁', text: 'Invite a friend with your code: you become friends the moment they join.' },
  ],

  // Who you can ask to be matched with. `premium: true` options need Premium.
  genderOptions: [
    { value: 'any', label: 'Anyone', emoji: '🌍', premium: false },
    { value: 'female', label: 'Female', emoji: '👩', premium: true },
    { value: 'male', label: 'Male', emoji: '👨', premium: true },
  ],

  matching: {
    // First line depends on the filter; the rest rotate while searching.
    headline: {
      any: 'Finding someone to talk to…',
      female: 'Looking for a female to talk to…',
      male: 'Looking for a male to talk to…',
    },
    messages: ['Scanning across the globe…', 'Good conversations are worth the wait…', 'Almost there…'],
  },

  premium: {
    title: 'VoxLink Premium',
    subtitle: 'Talk more. Choose who you talk to.',
    // {freeMinutes} and {premiumMinutes} are filled in from callLimits.
    benefits: [
      { emoji: '⏱️', title: '{premiumMinutes} minutes of calls a day', subtitle: 'Free users get {freeMinutes} minutes a day.' },
      { emoji: '🎯', title: 'Choose female or male', subtitle: 'Talk only to the people you want to meet.' },
      { emoji: '🔓', title: 'No auto-renewal', subtitle: 'Pay once for the period. No surprise charges.' },
    ],
    footer: 'One-time payment through Google Play. Does not renew automatically.',
  },

  reportReasons: [
    'Inappropriate or sexual content',
    'Harassment or hate speech',
    'Underage user',
    'Spam or scam',
    'Other',
  ],
};

module.exports = { PLANS, CONTENT, CONTENT_REVISION, REVISED_KEYS };
