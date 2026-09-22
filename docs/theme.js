/*!
 * MuffinEMU site theme engine — shared by every page.
 *
 * Real theme data, transcribed by hand from src/ios/App/MuffinThemePresets.swift
 * (light/dark hex pairs, 14 tokens per theme) and src/ios/App/MuffinTheme.swift
 * (the gradient math). Nothing here is invented:
 *
 *   - All 31 in-app themes are included: the 28 free ones plus the 3 "Pro" icon
 *     themes (Diamond Ice, Gold VIP, Holographic), which are unlocked in-app by a
 *     code (see PremiumUnlock.swift) rather than gated behind a store purchase.
 *     Pro themes are flagged `pro: true` below and labeled as such wherever the
 *     switcher shows a name, matching MuffinThemePresets.swift's own naming.
 *   - Every theme in MuffinThemePresets.swift is a flat two-color background
 *     EXCEPT "Autism Muffin", which is the one multi-stop gradient (a rainbow
 *     band across the header, spent in the top ~13% and holding cream for the
 *     rest) — see its `stops` field below.
 *   - Gradient direction matches MuffinTheme.swift's `backgroundGradient` exactly:
 *     flat two-color themes use SwiftUI's
 *     `LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)`,
 *     a 135deg corner-to-corner diagonal with even (0%/100%) stops in CSS terms.
 *     The one multi-stop theme uses `.top`/`.bottom`, i.e. 180deg top-to-bottom,
 *     because a diagonal would smear a header rainbow across the corners instead
 *     of keeping it in bands.
 *
 * Every page on the site loads this one file and shares one localStorage key, so
 * a theme picked on any page carries to every other page.
 */
(function (global) {
  "use strict";

  var THEMES = [
    { id: "bakery", name: "Bakery (Original)",
      top: ["#F4A551", "#935009"], bottom: ["#E6692D", "#512009"],
      muffinTop: ["#E3A254", "#C98A46"], muffinDark: ["#A8622A", "#8A4E20"],
      cream: ["#FDF6EC", "#241813"], wrapper: ["#F0DFC3", "#3A2A1E"],
      navy: ["#453765", "#8177AD"], pixel: ["#6C63FF", "#8A82FF"], blush: ["#F2A6A0", "#E08880"],
      brownDarkest: ["#2E1B10", "#FBEBD8"], brownDark: ["#5C2E10", "#E8CBA8"], brownMid: ["#7A4A22", "#C9A47C"],
      sparkle: ["#FFF3DD", "#FFF3DD"], shadow: ["#4A2410", "#000000"] },
    { id: "adhd-awareness", name: "ADHD Awareness",
      top: ["#FC9F61", "#9A3F03"], bottom: ["#E66815", "#602B09"],
      muffinTop: ["#E46E1F", "#E46E1F"], muffinDark: ["#A04D16", "#C45F1B"],
      cream: ["#FEF6F0", "#2B1D14"], wrapper: ["#FEE8DA", "#432D1F"],
      navy: ["#A3301F", "#D67466"], pixel: ["#EFD639", "#F7EA97"], blush: ["#E79341", "#F3C79B"],
      brownDarkest: ["#23160E", "#FFF8F4"], brownDark: ["#4B301E", "#FEEFE5"], brownMid: ["#865636", "#FDE1CD"],
      sparkle: ["#FDF6F2", "#FDF6F2"], shadow: ["#3C2618", "#000000"] },
    { id: "audhd-awareness", name: "AuDHD Awareness",
      top: ["#F7A617", "#754C04"], bottom: ["#B55A0E", "#4B2506"],
      muffinTop: ["#F8C868", "#F8C868"], muffinDark: ["#AE8C49", "#D5AC59"],
      cream: ["#FDF4E9", "#281B08"], wrapper: ["#FAE6CA", "#3E290D"],
      navy: ["#9D7425", "#D6B066"], pixel: ["#DA764E", "#EDB7A1"], blush: ["#D3D651", "#E7E9A5"],
      brownDarkest: ["#211505", "#FEF8F0"], brownDark: ["#472D0B", "#FCEDDA"], brownMid: ["#7F5113", "#F9DDB9"],
      sparkle: ["#FFFCF6", "#FFFCF6"], shadow: ["#382408", "#000000"] },
    { id: "autism-awareness", name: "Autism Muffin",
      top: ["#F5B5B5", "#6B4444"], bottom: ["#C9BCE6", "#514768"],
      muffinTop: ["#FFFEFF", "#FFFEFF"], muffinDark: ["#B2B2B2", "#DBDADB"],
      cream: ["#FFFFFF", "#2B2920"], wrapper: ["#E9E9EC", "#434031"],
      navy: ["#C62E2E", "#DD7D7D"], pixel: ["#B22A82", "#D666AE"], blush: ["#D65176", "#D66685"],
      brownDarkest: ["#222018", "#FEFDF9"], brownDark: ["#494533", "#FDFBF1"], brownMid: ["#837D5C", "#FBF7E4"],
      sparkle: ["#FFFFFF", "#FFFFFF"], shadow: ["#3A3729", "#000000"],
      stops: {
        light: ["#F5B5B5", "#F8D3A8", "#F3E7AB", "#BFE3B8", "#AFD4EC", "#C9BCE6", "#FFFFFF", "#FFFFFF"],
        dark: ["#6B4444", "#6E5A3E", "#6C674F", "#47603F", "#3F5568", "#514768", "#474435", "#474435"],
        locations: [0.00, 0.015, 0.03, 0.045, 0.06, 0.075, 0.13, 1.00]
      } },
    { id: "bisexual-pride", name: "Magenta Dusk",
      top: ["#D60270", "#600132"], bottom: ["#00349B", "#001641"],
      muffinTop: ["#0038A8", "#0038A8"], muffinDark: ["#002776", "#003090"],
      cream: ["#FBE6F1", "#240314"], wrapper: ["#F5C2DD", "#38041F"],
      navy: ["#0A43B8", "#668BD6"], pixel: ["#DCC04B", "#EEDEA0"], blush: ["#D68B51", "#EAC2A4"],
      brownDarkest: ["#1E0010", "#FCEDF5"], brownDark: ["#400122", "#F8D4E7"], brownMid: ["#74013C", "#F2AED1"],
      sparkle: ["#F0F3FA", "#F0F3FA"], shadow: ["#33001B", "#000000"] },
    { id: "blueberry-blast", name: "Blueberry Blast",
      top: ["#3E53DD", "#131F6C"], bottom: ["#2D409F", "#131B42"],
      muffinTop: ["#EACDA9", "#EACDA9"], muffinDark: ["#A49076", "#C9B091"],
      cream: ["#EEEFFA", "#101323"], wrapper: ["#D6D9F2", "#191D36"],
      navy: ["#9D6525", "#D6A266"], pixel: ["#27259F", "#6866D6"], blush: ["#5180D6", "#668DD6"],
      brownDarkest: ["#0C0E1C", "#F3F4FB"], brownDark: ["#191D3C", "#E2E4F6"], brownMid: ["#2D356C", "#C8CDED"],
      sparkle: ["#FEFCFA", "#FEFCFA"], shadow: ["#141830", "#000000"] },
    { id: "dark", name: "Dark Mode",
      top: ["#E1C7BF", "#7F4B3C"], bottom: ["#C1836B", "#583325"],
      muffinTop: ["#976842", "#976842"], muffinDark: ["#6A492E", "#825939"],
      cream: ["#FDFBF7", "#2A2621"], wrapper: ["#FBF5EC", "#423B33"],
      navy: ["#9D7625", "#D6B266"], pixel: ["#9D4A25", "#D68866"], blush: ["#9D252C", "#D6666D"],
      brownDarkest: ["#211E19", "#FEFCFA"], brownDark: ["#484035", "#FCF8F2"], brownMid: ["#817360", "#FAF2E6"],
      sparkle: ["#F9F6F4", "#F9F6F4"], shadow: ["#39332A", "#000000"] },
    { id: "disability-pride", name: "Disability Pride",
      top: ["#B54B53", "#522225"], bottom: ["#5C5C5C", "#272727"],
      muffinTop: ["#5F373B", "#5F373B"], muffinDark: ["#422629", "#522F33"],
      cream: ["#F9F3EC", "#22180C"], wrapper: ["#F1E1D0", "#352513"],
      navy: ["#9D2532", "#D66672"], pixel: ["#D6C251", "#E7DEA6"], blush: ["#D69251", "#E7C6A6"],
      brownDarkest: ["#1B1208", "#FBF6F1"], brownDark: ["#3B2712", "#F5EADE"], brownMid: ["#6A4720", "#ECD7C1"],
      sparkle: ["#F5F3F3", "#F5F3F3"], shadow: ["#2F1F0E", "#000000"] },
    { id: "double-chocolate", name: "Double Chocolate",
      top: ["#7B5032", "#372417"], bottom: ["#5D371F", "#27170D"],
      muffinTop: ["#482D1B", "#482D1B"], muffinDark: ["#321F13", "#3E2717"],
      cream: ["#F2EEEB", "#150F0A"], wrapper: ["#DFD5CE", "#21170F"],
      navy: ["#9D3025", "#D67066"], pixel: ["#D68F51", "#DEAC82"], blush: ["#D6BF51", "#E5D89B"],
      brownDarkest: ["#110B07", "#F6F3F1"], brownDark: ["#25180F", "#E8E1DC"], brownMid: ["#422B1C", "#D4C7BE"],
      sparkle: ["#F4F2F1", "#F4F2F1"], shadow: ["#1D130C", "#000000"] },
    { id: "equality", name: "Equality",
      top: ["#3444EC", "#0B1577"], bottom: ["#2F35A1", "#141643"],
      muffinTop: ["#EDCFA5", "#EDCFA5"], muffinDark: ["#A69173", "#CCB28E"],
      cream: ["#ECEEFC", "#0E1026"], wrapper: ["#D2D5F7", "#16193B"],
      navy: ["#9D6B25", "#D6A766"], pixel: ["#33259D", "#7366D6"], blush: ["#4E6FD5", "#6682D6"],
      brownDarkest: ["#0A0B1F", "#F2F3FD"], brownDark: ["#141842", "#DFE1F9"], brownMid: ["#252C77", "#C3C7F4"],
      sparkle: ["#FEFCFA", "#FEFCFA"], shadow: ["#101335", "#000000"] },
    { id: "fix-the-world", name: "Fix the World",
      top: ["#FFCFAD", "#C05100"], bottom: ["#7748EC", "#2A0C74"],
      muffinTop: ["#FCA1C5", "#FCA1C5"], muffinDark: ["#B0718A", "#D98AA9"],
      cream: ["#FFFAF7", "#2D2520"], wrapper: ["#FFF2EB", "#463932"],
      navy: ["#A12655", "#D66792"], pixel: ["#9C51D6", "#C49BE4"], blush: ["#CD51D6", "#E3A6E7"],
      brownDarkest: ["#241C18", "#FFFBF9"], brownDark: ["#4D3C34", "#FFF6F1"], brownMid: ["#8A6D5D", "#FFEEE5"],
      sparkle: ["#FFF9FC", "#FFF9FC"], shadow: ["#3D302A", "#000000"] },
    { id: "galaxy-space", name: "Galaxy Space",
      top: ["#BAA7EA", "#422292"], bottom: ["#6748D9", "#251563"],
      muffinTop: ["#291659", "#291659"], muffinDark: ["#1D0F3E", "#23134D"],
      cream: ["#FDFAF6", "#29251F"], wrapper: ["#FAF3EA", "#403930"],
      navy: ["#44259D", "#8366D6"], pixel: ["#222FA0", "#6672D6"], blush: ["#70259D", "#AD66D6"],
      brownDarkest: ["#211D17", "#FEFCF9"], brownDark: ["#463E32", "#FBF6F0"], brownMid: ["#7E6F5A", "#F8EFE3"],
      sparkle: ["#F2F1F5", "#F2F1F5"], shadow: ["#383128", "#000000"] },
    { id: "happy", name: "Happy",
      top: ["#F796C7", "#A60D5A"], bottom: ["#832AF4", "#350671"],
      muffinTop: ["#CB92ED", "#CB92ED"], muffinDark: ["#8E66A6", "#AF7ECC"],
      cream: ["#FEF5FA", "#2B1D25"], wrapper: ["#FCE7F3", "#422D3A"],
      navy: ["#72259D", "#AE66D6"], pixel: ["#ED843B", "#F4BF9A"], blush: ["#E44B44", "#F1A19D"],
      brownDarkest: ["#22161D", "#FEF8FC"], brownDark: ["#492F3E", "#FDEEF7"], brownMid: ["#835470", "#FBDFF0"],
      sparkle: ["#FCF8FE", "#FCF8FE"], shadow: ["#3A2532", "#000000"] },
    { id: "holiday-frost", name: "Holiday Frost",
      top: ["#A6D4F0", "#1B6A9B"], bottom: ["#5B91C9", "#1E3D5C"],
      muffinTop: ["#7EACD8", "#7EACD8"], muffinDark: ["#587897", "#6C94BA"],
      cream: ["#F6FAFD", "#1F252A"], wrapper: ["#EBF4FA", "#313A41"],
      navy: ["#25649D", "#66A1D6"], pixel: ["#CF9131", "#D6AA66"], blush: ["#D67251", "#DB8F76"],
      brownDarkest: ["#181D21", "#F9FCFE"], brownDark: ["#333F47", "#F1F7FC"], brownMid: ["#5C717F", "#E4F0F9"],
      sparkle: ["#F7FAFD", "#F7FAFD"], shadow: ["#293239", "#000000"] },
    { id: "lemon-zest", name: "Lemon Zest",
      top: ["#FFE67C", "#AB8A00"], bottom: ["#FFBE12", "#725300"],
      muffinTop: ["#FDF2BE", "#FDF2BE"], muffinDark: ["#B1A985", "#DAD0A3"],
      cream: ["#FFFCF2", "#2C2818"], wrapper: ["#FFF9E0", "#453F25"],
      navy: ["#AD9428", "#D8C56E"], pixel: ["#51D6BA", "#71DDC6"], blush: ["#51C2D6", "#91D5E2"],
      brownDarkest: ["#242012", "#FFFDF6"], brownDark: ["#4C4526", "#FFFBE9"], brownMid: ["#897C44", "#FFF7D5"],
      sparkle: ["#FFFEFB", "#FFFEFB"], shadow: ["#3D371E", "#000000"] },
    { id: "lesbian-pride", name: "Sunset Coral",
      top: ["#962E0F", "#441507"], bottom: ["#770047", "#32001E"],
      muffinTop: ["#F18B70", "#F18B70"], muffinDark: ["#A9614E", "#CF7860"],
      cream: ["#F5E6EF", "#1B0311"], wrapper: ["#E8C3D8", "#2A041A"],
      navy: ["#9D6025", "#D69E66"], pixel: ["#D53C25", "#E06E5C"], blush: ["#D65171", "#DC718A"],
      brownDarkest: ["#16010D", "#F8EEF4"], brownDark: ["#30021C", "#EFD5E4"], brownMid: ["#560333", "#E0AFCB"],
      sparkle: ["#FEF8F6", "#FEF8F6"], shadow: ["#260117", "#000000"] },
    { id: "mental-health-pride", name: "Mental Health Pride",
      top: ["#4BA35C", "#224929"], bottom: ["#357649", "#16311E"],
      muffinTop: ["#7ABF8C", "#7ABF8C"], muffinDark: ["#558662", "#69A478"],
      cream: ["#F6F2EC", "#1E170D"], wrapper: ["#EBE0D2", "#2E2315"],
      navy: ["#259D54", "#66D692"], pixel: ["#7FD651", "#9BDB79"], blush: ["#51D655", "#95E397"],
      brownDarkest: ["#18120A", "#F9F6F2"], brownDark: ["#332614", "#F1E9DF"], brownMid: ["#5C4425", "#E4D6C3"],
      sparkle: ["#F7FBF8", "#F7FBF8"], shadow: ["#291E10", "#000000"] },
    { id: "mint-matcha", name: "Mint Matcha",
      top: ["#63D79A", "#1D7045"], bottom: ["#3BA775", "#194530"],
      muffinTop: ["#A8E4C6", "#A8E4C6"], muffinDark: ["#76A08B", "#90C4AA"],
      cream: ["#F1FAF5", "#15231C"], wrapper: ["#DDF2E6", "#21372B"],
      navy: ["#259D61", "#66D69E"], pixel: ["#B5D651", "#D7E7A6"], blush: ["#D6C751", "#E7E0A6"],
      brownDarkest: ["#101C15", "#F5FBF8"], brownDark: ["#223C2E", "#E7F6ED"], brownMid: ["#3D6D52", "#D2EEDE"],
      sparkle: ["#FAFDFC", "#FAFDFC"], shadow: ["#1B3024", "#000000"] },
    { id: "neon-cyber", name: "Neon Cyber",
      top: ["#11091E", "#07040D"], bottom: ["#0B0616", "#040209"],
      muffinTop: ["#233453", "#233453"], muffinDark: ["#18243A", "#1E2D47"],
      cream: ["#E6E7E8", "#020305"], wrapper: ["#C4C6C9", "#030508"],
      navy: ["#254D9D", "#668BD6"], pixel: ["#5C259D", "#9966D6"], blush: ["#30259D", "#7066D6"],
      brownDarkest: ["#010304", "#EEEEEF"], brownDark: ["#030509", "#D5D7D9"], brownMid: ["#050A10", "#B0B3B7"],
      sparkle: ["#F2F3F5", "#F2F3F5"], shadow: ["#020407", "#000000"] },
    { id: "nonbinary-pride", name: "Lemon & Lilac",
      top: ["#FCF434", "#878202"], bottom: ["#6E6E6E", "#2E2E2E"],
      muffinTop: ["#A56BCF", "#A56BCF"], muffinDark: ["#734B91", "#8E5CB2"],
      cream: ["#FFFEEB", "#2B2A0C"], wrapper: ["#FEFCCE", "#434112"],
      navy: ["#6B259D", "#A766D6"], pixel: ["#D9BC4F", "#EBDBA3"], blush: ["#D68951", "#E8C2A6"],
      brownDarkest: ["#232207", "#FFFEF1"], brownDark: ["#4C4910", "#FEFDDC"], brownMid: ["#88841C", "#FEFBBE"],
      sparkle: ["#FAF6FC", "#FAF6FC"], shadow: ["#3C3B0C", "#000000"] },
    { id: "pro-diamond-ice", name: "Diamond Ice", pro: true,
      top: ["#DBEFFB", "#137CC0"], bottom: ["#6EB7E4", "#165277"],
      muffinTop: ["#9ACAE8", "#9ACAE8"], muffinDark: ["#6C8DA2", "#84AEC8"],
      cream: ["#FBFDFF", "#282B2D"], wrapper: ["#F6FBFE", "#3E4346"],
      navy: ["#256E9D", "#66AAD6"], pixel: ["#D65173", "#DD718D"], blush: ["#D651A4", "#E291C3"],
      brownDarkest: ["#1F2123", "#FCFEFF"], brownDark: ["#42474B", "#F9FCFE"], brownMid: ["#768188", "#F3FAFE"],
      sparkle: ["#F9FCFE", "#F9FCFE"], shadow: ["#35393C", "#000000"] },
    { id: "pro-gold-vip", name: "Gold VIP", pro: true,
      top: ["#F8C522", "#7B5F04"], bottom: ["#B47C17", "#4C3409"],
      muffinTop: ["#F7CD61", "#F7CD61"], muffinDark: ["#AD9044", "#D4B053"],
      cream: ["#FDF7EA", "#291F0A"], wrapper: ["#FAEDCD", "#3F3110"],
      navy: ["#999D25", "#D2D666"], pixel: ["#A94519", "#D68866"], blush: ["#D6A94F", "#D6B166"],
      brownDarkest: ["#211906", "#FEFAF0"], brownDark: ["#47350E", "#FCF2DB"], brownMid: ["#7F6019", "#F9E6BC"],
      sparkle: ["#FFFCF6", "#FFFCF6"], shadow: ["#392B0B", "#000000"] },
    { id: "pro-holographic", name: "Holographic", pro: true,
      top: ["#E3B3E8", "#842A8E"], bottom: ["#7047E1", "#29116B"],
      muffinTop: ["#ACEEE8", "#ACEEE8"], muffinDark: ["#78A7A2", "#94CDC8"],
      cream: ["#F6FCFE", "#1F272B"], wrapper: ["#EAF7FC", "#303D43"],
      navy: ["#25A093", "#66D6CB"], pixel: ["#BA51D6", "#DAA5E9"], blush: ["#8951D6", "#C2A6E7"],
      brownDarkest: ["#181F22", "#F9FDFE"], brownDark: ["#324249", "#F0F9FD"], brownMid: ["#5B7783", "#E3F4FB"],
      sparkle: ["#FAFEFE", "#FAFEFE"], shadow: ["#28353A", "#000000"] },
    { id: "progress-pride", name: "Chevron",
      top: ["#C4BBC0", "#5C5156"], bottom: ["#9149CB", "#3D195A"],
      muffinTop: ["#DC7B66", "#DC7B66"], muffinDark: ["#9A5647", "#BD6A58"],
      cream: ["#FFFBF2", "#2C2619"], wrapper: ["#FFF5E1", "#453B26"],
      navy: ["#9D3A25", "#D67A66"], pixel: ["#6E51D6", "#8C77DB"], blush: ["#9F51D6", "#C193E2"],
      brownDarkest: ["#231E12", "#FFFCF6"], brownDark: ["#4C4027", "#FFF8EA"], brownMid: ["#897346", "#FEF2D7"],
      sparkle: ["#FDF7F6", "#FDF7F6"], shadow: ["#3D331F", "#000000"] },
    { id: "pumpkin-spice", name: "Pumpkin Spice",
      top: ["#E5B496", "#894921"], bottom: ["#D17440", "#5C2F16"],
      muffinTop: ["#C16D38", "#C16D38"], muffinDark: ["#874C27", "#A65E30"],
      cream: ["#FDF9F4", "#29221B"], wrapper: ["#F9F0E5", "#40352B"],
      navy: ["#9D7C25", "#D6B866"], pixel: ["#9D2525", "#D66667"], blush: ["#D37743", "#D68E66"],
      brownDarkest: ["#201B15", "#FDFBF7"], brownDark: ["#46392C", "#FBF4ED"], brownMid: ["#7D674F", "#F8EBDC"],
      sparkle: ["#FBF6F3", "#FBF6F3"], shadow: ["#382E23", "#000000"] },
    { id: "rainbow-pride", name: "Full Spectrum",
      top: ["#FF7D4B", "#952900"], bottom: ["#0700EF", "#030063"],
      muffinTop: ["#CBE36A", "#CBE36A"], muffinDark: ["#8E9F4A", "#AFC35B"],
      cream: ["#FFF9ED", "#2C230F"], wrapper: ["#FFF1D4", "#443618"],
      navy: ["#869D25", "#C1D666"], pixel: ["#50D86B", "#87E49A"], blush: ["#68D651", "#AFE7A4"],
      brownDarkest: ["#241B0B", "#FFFBF2"], brownDark: ["#4D3B17", "#FFF5E0"], brownMid: ["#8A6A28", "#FFECC5"],
      sparkle: ["#FCFDF6", "#FCFDF6"], shadow: ["#3D2F12", "#000000"] },
    { id: "retro", name: "Retro Console",
      top: ["#C0B0D6", "#533D72"], bottom: ["#7A55C4", "#311E57"],
      muffinTop: ["#422869", "#422869"], muffinDark: ["#2E1C4A", "#39225A"],
      cream: ["#FCF9F6", "#28241E"], wrapper: ["#F8F2E9", "#3E382F"],
      navy: ["#54259D", "#9266D6"], pixel: ["#AF3F29", "#D67966"], blush: ["#D69851", "#D6A266"],
      brownDarkest: ["#201C17", "#FDFBF9"], brownDark: ["#443C31", "#FAF5EF"], brownMid: ["#7B6B58", "#F6EDE2"],
      sparkle: ["#F4F2F6", "#F4F2F6"], shadow: ["#363027", "#000000"] },
    { id: "spooky-halloween", name: "Spooky Halloween",
      top: ["#643286", "#2D173C"], bottom: ["#461F65", "#1E0D2B"],
      muffinTop: ["#351C47", "#351C47"], muffinDark: ["#251432", "#2E183D"],
      cream: ["#F2EDEB", "#170F0B"], wrapper: ["#E1D5CF", "#231711"],
      navy: ["#6A259D", "#A766D6"], pixel: ["#D68751", "#E7BEA3"], blush: ["#D65651", "#E7A9A6"],
      brownDarkest: ["#120B08", "#F6F3F1"], brownDark: ["#271811", "#EAE1DD"], brownMid: ["#462B1E", "#D7C7BF"],
      sparkle: ["#F3F1F4", "#F3F1F4"], shadow: ["#1F130D", "#000000"] },
    { id: "strawberry", name: "Strawberry",
      top: ["#FFBFD1", "#C90037"], bottom: ["#FF4276", "#860025"],
      muffinTop: ["#F8E7DB", "#F8E7DB"], muffinDark: ["#AEA299", "#D5C7BC"],
      cream: ["#FFF9FA", "#2D2326"], wrapper: ["#FFF0F4", "#46373B"],
      navy: ["#B6602B", "#DA9B74"], pixel: ["#7AD651", "#92DD71"], blush: ["#51D65A", "#91E296"],
      brownDarkest: ["#241B1D", "#FFFBFC"], brownDark: ["#4D393F", "#FFF4F7"], brownMid: ["#8A6771", "#FFEBF0"],
      sparkle: ["#FFFEFD", "#FFFEFD"], shadow: ["#3D2E32", "#000000"] },
    { id: "summer-beach", name: "Summer Beach",
      top: ["#29ABAA", "#124D4C"], bottom: ["#1B6F7E", "#0B2F35"],
      muffinTop: ["#4DBDC6", "#4DBDC6"], muffinDark: ["#36848B", "#42A3AA"],
      cream: ["#EAF5F7", "#091A1D"], wrapper: ["#CCE6EB", "#0E292E"],
      navy: ["#25949D", "#66CED6"], pixel: ["#C8662F", "#D68E66"], blush: ["#D6B251", "#D9BD72"],
      brownDarkest: ["#061518", "#F0F8F9"], brownDark: ["#0C2E33", "#DBEDF1"], brownMid: ["#16525C", "#BBDEE4"],
      sparkle: ["#F4FBFC", "#F4FBFC"], shadow: ["#0A2429", "#000000"] },
    { id: "transgender-pride", name: "Sky & Blush",
      top: ["#5BCEFA", "#056D94"], bottom: ["#07AEEE", "#034964"],
      muffinTop: ["#F3A9B8", "#F3A9B8"], muffinDark: ["#AA7681", "#D1919E"],
      cream: ["#EFFAFE", "#12242B"], wrapper: ["#D8F3FE", "#1C3943"],
      navy: ["#A0263D", "#D6667B"], pixel: ["#51A3D6", "#A6CEE7"], blush: ["#5173D6", "#A6B7E7"],
      brownDarkest: ["#0D1D23", "#F4FCFF"], brownDark: ["#1B3E4B", "#E3F7FE"], brownMid: ["#316F87", "#CBEFFD"],
      sparkle: ["#FEFAFB", "#FEFAFB"], shadow: ["#16313C", "#000000"] }
  ];

  var STORE_KEY = "muffinemu.site.themeId";

  function isDark() {
    return !!(global.matchMedia && global.matchMedia("(prefers-color-scheme: dark)").matches);
  }

  function pick(pair) { return isDark() ? pair[1] : pair[0]; }

  function findIndexById(id) {
    for (var i = 0; i < THEMES.length; i++) {
      if (THEMES[i].id === id) return i;
    }
    return -1;
  }

  function applyTheme(theme) {
    var root = document.documentElement.style;
    function set(name, val) { root.setProperty(name, val); }

    set("--bg-top", pick(theme.top));
    set("--bg-bottom", pick(theme.bottom));
    set("--muffin-top-light", pick(theme.muffinTop));
    set("--muffin-top-dark", pick(theme.muffinDark));
    set("--cream", pick(theme.cream));
    set("--wrapper", pick(theme.wrapper));
    set("--navy", pick(theme.navy));
    set("--pixel-blue", pick(theme.pixel));
    set("--blush", pick(theme.blush));
    set("--brown-darkest", pick(theme.brownDarkest));
    set("--brown-dark", pick(theme.brownDark));
    set("--brown-mid", pick(theme.brownMid));
    set("--sparkle", pick(theme.sparkle));
    set("--shadow", pick(theme.shadow));

    if (theme.stops) {
      var stops = isDark() ? theme.stops.dark : theme.stops.light;
      var locs = theme.stops.locations;
      var stopStr = stops.map(function (c, i) { return c + " " + (locs[i] * 100).toFixed(1) + "%"; }).join(", ");
      // Multi-stop themes: SwiftUI's .top -> .bottom, i.e. straight down the screen.
      set("--bg-image", "linear-gradient(180deg, " + stopStr + ")");
    } else {
      // Flat two-color themes: SwiftUI's .topLeading -> .bottomTrailing, i.e. a
      // 135deg diagonal with the two colors spaced evenly. Not an invented angle.
      set("--bg-image", "linear-gradient(135deg, var(--bg-top), var(--bg-bottom))");
    }

    var meta = document.getElementById("themeColorMeta");
    if (meta) meta.setAttribute("content", pick(theme.top));

    document.querySelectorAll("[data-theme-name]").forEach(function (el) {
      el.textContent = theme.name + (theme.pro ? " (Pro)" : "");
    });

    document.querySelectorAll("[data-theme-option]").forEach(function (el) {
      var on = el.getAttribute("data-theme-option") === theme.id;
      el.setAttribute("aria-pressed", on ? "true" : "false");
      if (on && el.scrollIntoView) el.scrollIntoView({ block: "nearest" });
    });

    document.querySelectorAll("[data-theme-swatches]").forEach(function (el) {
      el.innerHTML = "";
      [theme.top, theme.navy, theme.pixel, theme.blush].forEach(function (pair) {
        var i = document.createElement("i");
        i.style.background = pick(pair);
        el.appendChild(i);
      });
    });
  }

  var currentIndex = 0;

  function setThemeByIndex(i, persist) {
    currentIndex = ((i % THEMES.length) + THEMES.length) % THEMES.length;
    var theme = THEMES[currentIndex];
    applyTheme(theme);
    if (persist) {
      try { localStorage.setItem(STORE_KEY, theme.id); } catch (e) { /* private mode, etc. */ }
    }
    return theme;
  }

  // A single polite live region, created once. Cycling themes changes the button's
  // own label, and a label that mutates under the cursor is announced
  // inconsistently across screen readers; an explicit live region is not.
  var liveRegion = null;
  function announce(text) {
    if (!liveRegion) {
      liveRegion = document.createElement("div");
      liveRegion.setAttribute("aria-live", "polite");
      liveRegion.className = "visually-hidden";
      document.body.appendChild(liveRegion);
    }
    liveRegion.textContent = text;
  }

  // The picker. Built in JS rather than written into every page's HTML so the 31
  // names live in exactly one place - this file, next to the data they come from.
  // Every page that has the markup gets it; pages that do not are unaffected, and
  // with JS off the cycle button is simply the only control, as before.
  function buildPicker() {
    var panel = document.querySelector("[data-theme-panel]");
    var toggle = document.querySelector("[data-theme-menu]");
    if (!panel || !toggle) return;

    var heading = document.createElement("h4");
    heading.textContent = THEMES.length + " themes, from the app itself";
    panel.appendChild(heading);

    var list = document.createElement("div");
    list.className = "theme-list";
    THEMES.forEach(function (theme, i) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "theme-option";
      b.setAttribute("data-theme-option", theme.id);
      b.setAttribute("aria-pressed", "false");

      var dot = document.createElement("span");
      dot.className = "dot";
      // The real two-colour background, at the real 135deg, so the swatch is the
      // theme rather than an approximation of it.
      dot.style.background = "linear-gradient(135deg, " + pick(theme.top) + ", " + pick(theme.bottom) + ")";
      b.appendChild(dot);

      var nm = document.createElement("span");
      nm.className = "nm";
      nm.textContent = theme.name + (theme.pro ? " (Pro)" : "");
      b.appendChild(nm);

      b.addEventListener("click", function () {
        setThemeByIndex(i, true);
        announce(theme.name + " theme applied");
        close();
      });
      list.appendChild(b);
    });
    panel.appendChild(list);

    function open() {
      panel.hidden = false;
      toggle.setAttribute("aria-expanded", "true");
      var sel = panel.querySelector('[aria-pressed="true"]') || panel.querySelector(".theme-option");
      if (sel) sel.focus();
    }
    function close() {
      panel.hidden = true;
      toggle.setAttribute("aria-expanded", "false");
    }

    toggle.hidden = false;
    toggle.addEventListener("click", function () {
      if (panel.hidden) { open(); } else { close(); }
    });

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && !panel.hidden) { close(); toggle.focus(); }
    });
    document.addEventListener("click", function (e) {
      if (panel.hidden) return;
      if (!panel.contains(e.target) && e.target !== toggle && !toggle.contains(e.target)) close();
    });
  }

  function init() {
    var startIndex = 0;
    try {
      var savedId = localStorage.getItem(STORE_KEY);
      if (savedId) {
        var found = findIndexById(savedId);
        if (found >= 0) startIndex = found;
      }
    } catch (e) { /* private mode, etc. */ }
    setThemeByIndex(startIndex, false);

    buildPicker();

    document.querySelectorAll("[data-theme-cycle]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var t = setThemeByIndex(currentIndex + 1, true);
        announce(t.name + " theme applied");
      });
    });

    if (global.matchMedia) {
      global.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function () {
        applyTheme(THEMES[currentIndex]);
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  function setById(id, persist) {
    var found = findIndexById(id);
    if (found < 0) return null;
    return setThemeByIndex(found, persist !== false);
  }

  // Exposed in case a page wants the raw list (e.g. the Themes & Icons doc page,
  // which renders a swatch grid of all 31 and lets you click one directly).
  global.MuffinThemes = { THEMES: THEMES, STORE_KEY: STORE_KEY, setById: setById };
})(window);
