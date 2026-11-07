// Initial values for the database-driven app content and plans.
//
// These are only used to seed an empty database (and to add keys introduced
// by later versions). After that the database is the source of truth: edit
// through the admin API, not here.

const PLANS = [
  { id: 'weekly', title: 'Weekly', amountPaise: 49900, days: 7, badge: null, sortOrder: 1 },
  { id: 'monthly', title: 'Monthly', amountPaise: 99900, days: 30, badge: 'MOST POPULAR', sortOrder: 2 },
  { id: 'yearly', title: 'Yearly', amountPaise: 499900, days: 365, badge: 'BEST VALUE · SAVE 80%', sortOrder: 3 },
];

const CONTENT = {
  // Whether choosing who you talk to needs Premium. Off: everyone can pick any
  // gender for free and the app hides Premium. Switch it in the admin dashboard.
  premiumEnabled: false,

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
    { emoji: '👑', text: 'Premium lets you choose to talk only with women or men.', premium: true },
    { emoji: '🎁', text: 'Invite a friend with your code: you become friends the moment they join.' },
  ],

  // Who you can ask to be matched with. `premium: true` options need Premium.
  genderOptions: [
    { value: 'any', label: 'Anyone', emoji: '🌍', premium: false },
    { value: 'female', label: 'Women', emoji: '👩', premium: true },
    { value: 'male', label: 'Men', emoji: '👨', premium: true },
  ],

  matching: {
    // First line depends on the filter; the rest rotate while searching.
    headline: {
      any: 'Finding someone to talk to…',
      female: 'Looking for a woman to talk to…',
      male: 'Looking for a man to talk to…',
    },
    messages: ['Scanning across the globe…', 'Good conversations are worth the wait…', 'Almost there…'],
  },

  premium: {
    title: 'VoxLink Premium',
    subtitle: 'Choose who you talk to.',
    benefits: [
      { emoji: '👩', title: 'Talk only to women', subtitle: 'Pick who you want to meet, every time.' },
      { emoji: '👨', title: 'Talk only to men', subtitle: 'Switch your preference whenever you like.' },
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

module.exports = { PLANS, CONTENT };
