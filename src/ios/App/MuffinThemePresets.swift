import Foundation

// GENERATED derivation, not hand-tuned art direction - see the comment on
// MuffinThemeDefinition in MuffinThemeStore.swift for exactly how. Each theme's 14
// tokens are computed from that icon's own real icon.png (median-cut quantized top
// swatches, picked by saturation/lightness for a primary+secondary+accent triad, then
// lightened/darkened/desaturated by fixed formulas - the same lighten-for-dark-accents,
// deepen-and-desaturate-for-dark-backgrounds, flip-text-light-dark relationships
// MuffinTheme's own hand-tuned Bakery theme already documents by hand, just applied
// uniformly across all thirty icons instead of judged one at a time. That means some
// of these will read better than others - a from-scratch art pass per icon was out of
// scope here - but every value traces back to a real pixel in that icon's actual art,
// never an invented hex code.
enum MuffinThemePresets {

    /// The app's original, hand-tuned palette (see MuffinTheme.swift's own header
    /// comment) - kept as literal constants rather than re-derived, so switching this
    /// theme system in changes nothing for anyone who never opens the theme picker.
    static let bakery = MuffinThemeDefinition(
        id: "bakery", name: "Bakery (Original)", iconId: "original",
        backgroundTopLight: "#F4A551", backgroundTopDark: "#935009",
        backgroundBottomLight: "#E6692D", backgroundBottomDark: "#512009",
        muffinTopLightLight: "#E3A254", muffinTopLightDark: "#C98A46",
        muffinTopDarkLight: "#A8622A", muffinTopDarkDark: "#8A4E20",
        creamLight: "#FDF6EC", creamDark: "#241813",
        wrapperLight: "#F0DFC3", wrapperDark: "#3A2A1E",
        blueberryNavyLight: "#453765", blueberryNavyDark: "#8177AD",
        pixelBlueLight: "#6C63FF", pixelBlueDark: "#8A82FF",
        blushPinkLight: "#F2A6A0", blushPinkDark: "#E08880",
        brownDarkestLight: "#2E1B10", brownDarkestDark: "#FBEBD8",
        brownDarkLight: "#5C2E10", brownDarkDark: "#E8CBA8",
        brownMidLight: "#7A4A22", brownMidDark: "#C9A47C",
        sparkleCreamLight: "#FFF3DD", sparkleCreamDark: "#FFF3DD",
        shadowLight: "#4A2410", shadowDark: "#000000"
    )

    static let adhdAwareness = MuffinThemeDefinition(
        id: "adhd-awareness", name: "ADHD Awareness", iconId: "adhd-awareness",
        backgroundTopLight: "#FC9F61", backgroundTopDark: "#9A3F03",
        backgroundBottomLight: "#E66815", backgroundBottomDark: "#602B09",
        muffinTopLightLight: "#E46E1F", muffinTopLightDark: "#E46E1F",
        muffinTopDarkLight: "#A04D16", muffinTopDarkDark: "#C45F1B",
        creamLight: "#FEF6F0", creamDark: "#2B1D14",
        wrapperLight: "#FEE8DA", wrapperDark: "#432D1F",
        blueberryNavyLight: "#A3301F", blueberryNavyDark: "#D67466",
        pixelBlueLight: "#EFD639", pixelBlueDark: "#F7EA97",
        blushPinkLight: "#E79341", blushPinkDark: "#F3C79B",
        brownDarkestLight: "#23160E", brownDarkestDark: "#FFF8F4",
        brownDarkLight: "#4B301E", brownDarkDark: "#FEEFE5",
        brownMidLight: "#865636", brownMidDark: "#FDE1CD",
        sparkleCreamLight: "#FDF6F2", sparkleCreamDark: "#FDF6F2",
        shadowLight: "#3C2618", shadowDark: "#000000"
    )

    static let audhdAwareness = MuffinThemeDefinition(
        id: "audhd-awareness", name: "AuDHD Awareness", iconId: "audhd-awareness",
        backgroundTopLight: "#F7A617", backgroundTopDark: "#754C04",
        backgroundBottomLight: "#B55A0E", backgroundBottomDark: "#4B2506",
        muffinTopLightLight: "#F8C868", muffinTopLightDark: "#F8C868",
        muffinTopDarkLight: "#AE8C49", muffinTopDarkDark: "#D5AC59",
        creamLight: "#FDF4E9", creamDark: "#281B08",
        wrapperLight: "#FAE6CA", wrapperDark: "#3E290D",
        blueberryNavyLight: "#9D7425", blueberryNavyDark: "#D6B066",
        pixelBlueLight: "#DA764E", pixelBlueDark: "#EDB7A1",
        blushPinkLight: "#D3D651", blushPinkDark: "#E7E9A5",
        brownDarkestLight: "#211505", brownDarkestDark: "#FEF8F0",
        brownDarkLight: "#472D0B", brownDarkDark: "#FCEDDA",
        brownMidLight: "#7F5113", brownMidDark: "#F9DDB9",
        sparkleCreamLight: "#FFFCF6", sparkleCreamDark: "#FFFCF6",
        shadowLight: "#382408", shadowDark: "#000000"
    )

    /// Hand-adjusted, unlike its thirty siblings. The neurodiversity symbol this icon
    /// is drawn from is a rainbow infinity, and the generated two-stop derivation
    /// flattened that into a beige gradient - losing the one thing the icon is actually
    /// about. The header is a soft six-stop rainbow instead, and the cream/wrapper
    /// surfaces underneath it take the warm yellow the header used to be (#F3E7AB), so
    /// the palette the theme had is kept rather than discarded.
    ///
    /// Soft on purpose: pastel stops rather than saturated ones. A full-screen rainbow
    /// at full chroma behind an emulator is exhausting to sit in front of, and the
    /// middle stop is deliberately the old header colour so the theme still reads as
    /// itself.
    static let autismAwareness = MuffinThemeDefinition(
        id: "autism-awareness", name: "Autism Muffin", iconId: "autism-awareness",
        backgroundTopLight: "#F5B5B5", backgroundTopDark: "#6B4444",
        backgroundBottomLight: "#C9BCE6", backgroundBottomDark: "#514768",
        muffinTopLightLight: "#FFFEFF", muffinTopLightDark: "#FFFEFF",
        muffinTopDarkLight: "#B2B2B2", muffinTopDarkDark: "#DBDADB",
        // Plain white, like the frosting on this icon. cream is the big secondary
        // surface - the card under the library, Settings, the sheets.
        creamLight: "#FFFFFF", creamDark: "#2B2920",
        // wrapper is NOT white, deliberately, and cannot be. It is the 1pt stroke
        // around cards (ContentView.swift:638, :673) and the selected-row fill in
        // ControllerSkinsLibrary.swift:440, where the whole job is
        // `isSelected ? wrapper : cream`. Pure white there would erase every card
        // border and make selection invisible against a white cream. A faint
        // neutral reads as white next to the frosting while still drawing.
        wrapperLight: "#E9E9EC", wrapperDark: "#434031",
        blueberryNavyLight: "#C62E2E", blueberryNavyDark: "#DD7D7D",
        pixelBlueLight: "#B22A82", pixelBlueDark: "#D666AE",
        blushPinkLight: "#D65176", blushPinkDark: "#D66685",
        brownDarkestLight: "#222018", brownDarkestDark: "#FEFDF9",
        brownDarkLight: "#494533", brownDarkDark: "#FDFBF1",
        brownMidLight: "#837D5C", brownMidDark: "#FBF7E4",
        sparkleCreamLight: "#FFFFFF", sparkleCreamDark: "#FFFFFF",
        shadowLight: "#3A3729", shadowDark: "#000000",
        // The rainbow is spent in the top ~7.5% and then holds the cream for the rest.
        // The header is a thin band - the games card covers everything below it - so a
        // rainbow spread evenly over the full height would put nothing but red in the
        // only part of it anyone sees. 7.5% rather than a rounder number because the
        // strip is a fixed ~108-131pt against a screen height that varies by device:
        // too low and an iPhone shows cream in half its header, too high and an iPad
        // Pro loses violet off the bottom of the band.
        backgroundStopsLight: [
            "#F5B5B5",  // soft red
            "#F8D3A8",  // soft orange
            "#F3E7AB",  // soft yellow - the colour this header used to be
            "#BFE3B8",  // soft green
            "#AFD4EC",  // soft blue
            "#C9BCE6",  // soft violet
            "#FFFFFF",  // settles to the white the card underneath now uses
            "#FFFFFF",
        ],
        backgroundStopsDark: [
            "#6B4444",
            "#6E5A3E",
            "#6C674F",  // the colour this header used to be, in dark
            "#47603F",
            "#3F5568",
            "#514768",
            "#474435",  // the background bottom this theme already had, in dark
            "#474435",
        ],
        backgroundStopLocations: [0.00, 0.015, 0.03, 0.045, 0.06, 0.075, 0.13, 1.00]
    )

    static let bisexualPride = MuffinThemeDefinition(
        id: "bisexual-pride", name: "Bisexual Pride", iconId: "bisexual-pride",
        backgroundTopLight: "#D60270", backgroundTopDark: "#600132",
        backgroundBottomLight: "#00349B", backgroundBottomDark: "#001641",
        muffinTopLightLight: "#0038A8", muffinTopLightDark: "#0038A8",
        muffinTopDarkLight: "#002776", muffinTopDarkDark: "#003090",
        creamLight: "#FBE6F1", creamDark: "#240314",
        wrapperLight: "#F5C2DD", wrapperDark: "#38041F",
        blueberryNavyLight: "#0A43B8", blueberryNavyDark: "#668BD6",
        pixelBlueLight: "#DCC04B", pixelBlueDark: "#EEDEA0",
        blushPinkLight: "#D68B51", blushPinkDark: "#EAC2A4",
        brownDarkestLight: "#1E0010", brownDarkestDark: "#FCEDF5",
        brownDarkLight: "#400122", brownDarkDark: "#F8D4E7",
        brownMidLight: "#74013C", brownMidDark: "#F2AED1",
        sparkleCreamLight: "#F0F3FA", sparkleCreamDark: "#F0F3FA",
        shadowLight: "#33001B", shadowDark: "#000000"
    )

    static let blueberryBlast = MuffinThemeDefinition(
        id: "blueberry-blast", name: "Blueberry Blast", iconId: "blueberry-blast",
        backgroundTopLight: "#3E53DD", backgroundTopDark: "#131F6C",
        backgroundBottomLight: "#2D409F", backgroundBottomDark: "#131B42",
        muffinTopLightLight: "#EACDA9", muffinTopLightDark: "#EACDA9",
        muffinTopDarkLight: "#A49076", muffinTopDarkDark: "#C9B091",
        creamLight: "#EEEFFA", creamDark: "#101323",
        wrapperLight: "#D6D9F2", wrapperDark: "#191D36",
        blueberryNavyLight: "#9D6525", blueberryNavyDark: "#D6A266",
        pixelBlueLight: "#27259F", pixelBlueDark: "#6866D6",
        blushPinkLight: "#5180D6", blushPinkDark: "#668DD6",
        brownDarkestLight: "#0C0E1C", brownDarkestDark: "#F3F4FB",
        brownDarkLight: "#191D3C", brownDarkDark: "#E2E4F6",
        brownMidLight: "#2D356C", brownMidDark: "#C8CDED",
        sparkleCreamLight: "#FEFCFA", sparkleCreamDark: "#FEFCFA",
        shadowLight: "#141830", shadowDark: "#000000"
    )

    static let dark = MuffinThemeDefinition(
        id: "dark", name: "Dark Mode", iconId: "dark",
        backgroundTopLight: "#E1C7BF", backgroundTopDark: "#7F4B3C",
        backgroundBottomLight: "#C1836B", backgroundBottomDark: "#583325",
        muffinTopLightLight: "#976842", muffinTopLightDark: "#976842",
        muffinTopDarkLight: "#6A492E", muffinTopDarkDark: "#825939",
        creamLight: "#FDFBF7", creamDark: "#2A2621",
        wrapperLight: "#FBF5EC", wrapperDark: "#423B33",
        blueberryNavyLight: "#9D7625", blueberryNavyDark: "#D6B266",
        pixelBlueLight: "#9D4A25", pixelBlueDark: "#D68866",
        blushPinkLight: "#9D252C", blushPinkDark: "#D6666D",
        brownDarkestLight: "#211E19", brownDarkestDark: "#FEFCFA",
        brownDarkLight: "#484035", brownDarkDark: "#FCF8F2",
        brownMidLight: "#817360", brownMidDark: "#FAF2E6",
        sparkleCreamLight: "#F9F6F4", sparkleCreamDark: "#F9F6F4",
        shadowLight: "#39332A", shadowDark: "#000000"
    )

    static let disabilityPride = MuffinThemeDefinition(
        id: "disability-pride", name: "Disability Pride", iconId: "disability-pride",
        backgroundTopLight: "#B54B53", backgroundTopDark: "#522225",
        backgroundBottomLight: "#5C5C5C", backgroundBottomDark: "#272727",
        muffinTopLightLight: "#5F373B", muffinTopLightDark: "#5F373B",
        muffinTopDarkLight: "#422629", muffinTopDarkDark: "#522F33",
        creamLight: "#F9F3EC", creamDark: "#22180C",
        wrapperLight: "#F1E1D0", wrapperDark: "#352513",
        blueberryNavyLight: "#9D2532", blueberryNavyDark: "#D66672",
        pixelBlueLight: "#D6C251", pixelBlueDark: "#E7DEA6",
        blushPinkLight: "#D69251", blushPinkDark: "#E7C6A6",
        brownDarkestLight: "#1B1208", brownDarkestDark: "#FBF6F1",
        brownDarkLight: "#3B2712", brownDarkDark: "#F5EADE",
        brownMidLight: "#6A4720", brownMidDark: "#ECD7C1",
        sparkleCreamLight: "#F5F3F3", sparkleCreamDark: "#F5F3F3",
        shadowLight: "#2F1F0E", shadowDark: "#000000"
    )

    static let doubleChocolate = MuffinThemeDefinition(
        id: "double-chocolate", name: "Double Chocolate", iconId: "double-chocolate",
        backgroundTopLight: "#7B5032", backgroundTopDark: "#372417",
        backgroundBottomLight: "#5D371F", backgroundBottomDark: "#27170D",
        muffinTopLightLight: "#482D1B", muffinTopLightDark: "#482D1B",
        muffinTopDarkLight: "#321F13", muffinTopDarkDark: "#3E2717",
        creamLight: "#F2EEEB", creamDark: "#150F0A",
        wrapperLight: "#DFD5CE", wrapperDark: "#21170F",
        blueberryNavyLight: "#9D3025", blueberryNavyDark: "#D67066",
        pixelBlueLight: "#D68F51", pixelBlueDark: "#DEAC82",
        blushPinkLight: "#D6BF51", blushPinkDark: "#E5D89B",
        brownDarkestLight: "#110B07", brownDarkestDark: "#F6F3F1",
        brownDarkLight: "#25180F", brownDarkDark: "#E8E1DC",
        brownMidLight: "#422B1C", brownMidDark: "#D4C7BE",
        sparkleCreamLight: "#F4F2F1", sparkleCreamDark: "#F4F2F1",
        shadowLight: "#1D130C", shadowDark: "#000000"
    )

    static let equality = MuffinThemeDefinition(
        id: "equality", name: "Equality", iconId: "equality",
        backgroundTopLight: "#3444EC", backgroundTopDark: "#0B1577",
        backgroundBottomLight: "#2F35A1", backgroundBottomDark: "#141643",
        muffinTopLightLight: "#EDCFA5", muffinTopLightDark: "#EDCFA5",
        muffinTopDarkLight: "#A69173", muffinTopDarkDark: "#CCB28E",
        creamLight: "#ECEEFC", creamDark: "#0E1026",
        wrapperLight: "#D2D5F7", wrapperDark: "#16193B",
        blueberryNavyLight: "#9D6B25", blueberryNavyDark: "#D6A766",
        pixelBlueLight: "#33259D", pixelBlueDark: "#7366D6",
        blushPinkLight: "#4E6FD5", blushPinkDark: "#6682D6",
        brownDarkestLight: "#0A0B1F", brownDarkestDark: "#F2F3FD",
        brownDarkLight: "#141842", brownDarkDark: "#DFE1F9",
        brownMidLight: "#252C77", brownMidDark: "#C3C7F4",
        sparkleCreamLight: "#FEFCFA", sparkleCreamDark: "#FEFCFA",
        shadowLight: "#101335", shadowDark: "#000000"
    )

    static let fixTheWorld = MuffinThemeDefinition(
        id: "fix-the-world", name: "Fix the World", iconId: "fix-the-world",
        backgroundTopLight: "#FFCFAD", backgroundTopDark: "#C05100",
        backgroundBottomLight: "#7748EC", backgroundBottomDark: "#2A0C74",
        muffinTopLightLight: "#FCA1C5", muffinTopLightDark: "#FCA1C5",
        muffinTopDarkLight: "#B0718A", muffinTopDarkDark: "#D98AA9",
        creamLight: "#FFFAF7", creamDark: "#2D2520",
        wrapperLight: "#FFF2EB", wrapperDark: "#463932",
        blueberryNavyLight: "#A12655", blueberryNavyDark: "#D66792",
        pixelBlueLight: "#9C51D6", pixelBlueDark: "#C49BE4",
        blushPinkLight: "#CD51D6", blushPinkDark: "#E3A6E7",
        brownDarkestLight: "#241C18", brownDarkestDark: "#FFFBF9",
        brownDarkLight: "#4D3C34", brownDarkDark: "#FFF6F1",
        brownMidLight: "#8A6D5D", brownMidDark: "#FFEEE5",
        sparkleCreamLight: "#FFF9FC", sparkleCreamDark: "#FFF9FC",
        shadowLight: "#3D302A", shadowDark: "#000000"
    )

    static let galaxySpace = MuffinThemeDefinition(
        id: "galaxy-space", name: "Galaxy Space", iconId: "galaxy-space",
        backgroundTopLight: "#BAA7EA", backgroundTopDark: "#422292",
        backgroundBottomLight: "#6748D9", backgroundBottomDark: "#251563",
        muffinTopLightLight: "#291659", muffinTopLightDark: "#291659",
        muffinTopDarkLight: "#1D0F3E", muffinTopDarkDark: "#23134D",
        creamLight: "#FDFAF6", creamDark: "#29251F",
        wrapperLight: "#FAF3EA", wrapperDark: "#403930",
        blueberryNavyLight: "#44259D", blueberryNavyDark: "#8366D6",
        pixelBlueLight: "#222FA0", pixelBlueDark: "#6672D6",
        blushPinkLight: "#70259D", blushPinkDark: "#AD66D6",
        brownDarkestLight: "#211D17", brownDarkestDark: "#FEFCF9",
        brownDarkLight: "#463E32", brownDarkDark: "#FBF6F0",
        brownMidLight: "#7E6F5A", brownMidDark: "#F8EFE3",
        sparkleCreamLight: "#F2F1F5", sparkleCreamDark: "#F2F1F5",
        shadowLight: "#383128", shadowDark: "#000000"
    )

    static let happy = MuffinThemeDefinition(
        id: "happy", name: "Happy", iconId: "happy",
        backgroundTopLight: "#F796C7", backgroundTopDark: "#A60D5A",
        backgroundBottomLight: "#832AF4", backgroundBottomDark: "#350671",
        muffinTopLightLight: "#CB92ED", muffinTopLightDark: "#CB92ED",
        muffinTopDarkLight: "#8E66A6", muffinTopDarkDark: "#AF7ECC",
        creamLight: "#FEF5FA", creamDark: "#2B1D25",
        wrapperLight: "#FCE7F3", wrapperDark: "#422D3A",
        blueberryNavyLight: "#72259D", blueberryNavyDark: "#AE66D6",
        pixelBlueLight: "#ED843B", pixelBlueDark: "#F4BF9A",
        blushPinkLight: "#E44B44", blushPinkDark: "#F1A19D",
        brownDarkestLight: "#22161D", brownDarkestDark: "#FEF8FC",
        brownDarkLight: "#492F3E", brownDarkDark: "#FDEEF7",
        brownMidLight: "#835470", brownMidDark: "#FBDFF0",
        sparkleCreamLight: "#FCF8FE", sparkleCreamDark: "#FCF8FE",
        shadowLight: "#3A2532", shadowDark: "#000000"
    )

    static let holidayFrost = MuffinThemeDefinition(
        id: "holiday-frost", name: "Holiday Frost", iconId: "holiday-frost",
        backgroundTopLight: "#A6D4F0", backgroundTopDark: "#1B6A9B",
        backgroundBottomLight: "#5B91C9", backgroundBottomDark: "#1E3D5C",
        muffinTopLightLight: "#7EACD8", muffinTopLightDark: "#7EACD8",
        muffinTopDarkLight: "#587897", muffinTopDarkDark: "#6C94BA",
        creamLight: "#F6FAFD", creamDark: "#1F252A",
        wrapperLight: "#EBF4FA", wrapperDark: "#313A41",
        blueberryNavyLight: "#25649D", blueberryNavyDark: "#66A1D6",
        pixelBlueLight: "#CF9131", pixelBlueDark: "#D6AA66",
        blushPinkLight: "#D67251", blushPinkDark: "#DB8F76",
        brownDarkestLight: "#181D21", brownDarkestDark: "#F9FCFE",
        brownDarkLight: "#333F47", brownDarkDark: "#F1F7FC",
        brownMidLight: "#5C717F", brownMidDark: "#E4F0F9",
        sparkleCreamLight: "#F7FAFD", sparkleCreamDark: "#F7FAFD",
        shadowLight: "#293239", shadowDark: "#000000"
    )

    static let lemonZest = MuffinThemeDefinition(
        id: "lemon-zest", name: "Lemon Zest", iconId: "lemon-zest",
        backgroundTopLight: "#FFE67C", backgroundTopDark: "#AB8A00",
        backgroundBottomLight: "#FFBE12", backgroundBottomDark: "#725300",
        muffinTopLightLight: "#FDF2BE", muffinTopLightDark: "#FDF2BE",
        muffinTopDarkLight: "#B1A985", muffinTopDarkDark: "#DAD0A3",
        creamLight: "#FFFCF2", creamDark: "#2C2818",
        wrapperLight: "#FFF9E0", wrapperDark: "#453F25",
        blueberryNavyLight: "#AD9428", blueberryNavyDark: "#D8C56E",
        pixelBlueLight: "#51D6BA", pixelBlueDark: "#71DDC6",
        blushPinkLight: "#51C2D6", blushPinkDark: "#91D5E2",
        brownDarkestLight: "#242012", brownDarkestDark: "#FFFDF6",
        brownDarkLight: "#4C4526", brownDarkDark: "#FFFBE9",
        brownMidLight: "#897C44", brownMidDark: "#FFF7D5",
        sparkleCreamLight: "#FFFEFB", sparkleCreamDark: "#FFFEFB",
        shadowLight: "#3D371E", shadowDark: "#000000"
    )

    static let lesbianPride = MuffinThemeDefinition(
        id: "lesbian-pride", name: "Lesbian Pride", iconId: "lesbian-pride",
        backgroundTopLight: "#962E0F", backgroundTopDark: "#441507",
        backgroundBottomLight: "#770047", backgroundBottomDark: "#32001E",
        muffinTopLightLight: "#F18B70", muffinTopLightDark: "#F18B70",
        muffinTopDarkLight: "#A9614E", muffinTopDarkDark: "#CF7860",
        creamLight: "#F5E6EF", creamDark: "#1B0311",
        wrapperLight: "#E8C3D8", wrapperDark: "#2A041A",
        blueberryNavyLight: "#9D6025", blueberryNavyDark: "#D69E66",
        pixelBlueLight: "#D53C25", pixelBlueDark: "#E06E5C",
        blushPinkLight: "#D65171", blushPinkDark: "#DC718A",
        brownDarkestLight: "#16010D", brownDarkestDark: "#F8EEF4",
        brownDarkLight: "#30021C", brownDarkDark: "#EFD5E4",
        brownMidLight: "#560333", brownMidDark: "#E0AFCB",
        sparkleCreamLight: "#FEF8F6", sparkleCreamDark: "#FEF8F6",
        shadowLight: "#260117", shadowDark: "#000000"
    )

    static let mentalHealthPride = MuffinThemeDefinition(
        id: "mental-health-pride", name: "Mental Health Pride", iconId: "mental-health-pride",
        backgroundTopLight: "#4BA35C", backgroundTopDark: "#224929",
        backgroundBottomLight: "#357649", backgroundBottomDark: "#16311E",
        muffinTopLightLight: "#7ABF8C", muffinTopLightDark: "#7ABF8C",
        muffinTopDarkLight: "#558662", muffinTopDarkDark: "#69A478",
        creamLight: "#F6F2EC", creamDark: "#1E170D",
        wrapperLight: "#EBE0D2", wrapperDark: "#2E2315",
        blueberryNavyLight: "#259D54", blueberryNavyDark: "#66D692",
        pixelBlueLight: "#7FD651", pixelBlueDark: "#9BDB79",
        blushPinkLight: "#51D655", blushPinkDark: "#95E397",
        brownDarkestLight: "#18120A", brownDarkestDark: "#F9F6F2",
        brownDarkLight: "#332614", brownDarkDark: "#F1E9DF",
        brownMidLight: "#5C4425", brownMidDark: "#E4D6C3",
        sparkleCreamLight: "#F7FBF8", sparkleCreamDark: "#F7FBF8",
        shadowLight: "#291E10", shadowDark: "#000000"
    )

    static let mintMatcha = MuffinThemeDefinition(
        id: "mint-matcha", name: "Mint Matcha", iconId: "mint-matcha",
        backgroundTopLight: "#63D79A", backgroundTopDark: "#1D7045",
        backgroundBottomLight: "#3BA775", backgroundBottomDark: "#194530",
        muffinTopLightLight: "#A8E4C6", muffinTopLightDark: "#A8E4C6",
        muffinTopDarkLight: "#76A08B", muffinTopDarkDark: "#90C4AA",
        creamLight: "#F1FAF5", creamDark: "#15231C",
        wrapperLight: "#DDF2E6", wrapperDark: "#21372B",
        blueberryNavyLight: "#259D61", blueberryNavyDark: "#66D69E",
        pixelBlueLight: "#B5D651", pixelBlueDark: "#D7E7A6",
        blushPinkLight: "#D6C751", blushPinkDark: "#E7E0A6",
        brownDarkestLight: "#101C15", brownDarkestDark: "#F5FBF8",
        brownDarkLight: "#223C2E", brownDarkDark: "#E7F6ED",
        brownMidLight: "#3D6D52", brownMidDark: "#D2EEDE",
        sparkleCreamLight: "#FAFDFC", sparkleCreamDark: "#FAFDFC",
        shadowLight: "#1B3024", shadowDark: "#000000"
    )

    static let neonCyber = MuffinThemeDefinition(
        id: "neon-cyber", name: "Neon Cyber", iconId: "neon-cyber",
        backgroundTopLight: "#11091E", backgroundTopDark: "#07040D",
        backgroundBottomLight: "#0B0616", backgroundBottomDark: "#040209",
        muffinTopLightLight: "#233453", muffinTopLightDark: "#233453",
        muffinTopDarkLight: "#18243A", muffinTopDarkDark: "#1E2D47",
        creamLight: "#E6E7E8", creamDark: "#020305",
        wrapperLight: "#C4C6C9", wrapperDark: "#030508",
        blueberryNavyLight: "#254D9D", blueberryNavyDark: "#668BD6",
        pixelBlueLight: "#5C259D", pixelBlueDark: "#9966D6",
        blushPinkLight: "#30259D", blushPinkDark: "#7066D6",
        brownDarkestLight: "#010304", brownDarkestDark: "#EEEEEF",
        brownDarkLight: "#030509", brownDarkDark: "#D5D7D9",
        brownMidLight: "#050A10", brownMidDark: "#B0B3B7",
        sparkleCreamLight: "#F2F3F5", sparkleCreamDark: "#F2F3F5",
        shadowLight: "#020407", shadowDark: "#000000"
    )

    static let nonbinaryPride = MuffinThemeDefinition(
        id: "nonbinary-pride", name: "Nonbinary Pride", iconId: "nonbinary-pride",
        backgroundTopLight: "#FCF434", backgroundTopDark: "#878202",
        backgroundBottomLight: "#6E6E6E", backgroundBottomDark: "#2E2E2E",
        muffinTopLightLight: "#A56BCF", muffinTopLightDark: "#A56BCF",
        muffinTopDarkLight: "#734B91", muffinTopDarkDark: "#8E5CB2",
        creamLight: "#FFFEEB", creamDark: "#2B2A0C",
        wrapperLight: "#FEFCCE", wrapperDark: "#434112",
        blueberryNavyLight: "#6B259D", blueberryNavyDark: "#A766D6",
        pixelBlueLight: "#D9BC4F", pixelBlueDark: "#EBDBA3",
        blushPinkLight: "#D68951", blushPinkDark: "#E8C2A6",
        brownDarkestLight: "#232207", brownDarkestDark: "#FFFEF1",
        brownDarkLight: "#4C4910", brownDarkDark: "#FEFDDC",
        brownMidLight: "#88841C", brownMidDark: "#FEFBBE",
        sparkleCreamLight: "#FAF6FC", sparkleCreamDark: "#FAF6FC",
        shadowLight: "#3C3B0C", shadowDark: "#000000"
    )

    static let proDiamondIce = MuffinThemeDefinition(
        id: "pro-diamond-ice", name: "Diamond Ice", iconId: "pro-diamond-ice",
        backgroundTopLight: "#DBEFFB", backgroundTopDark: "#137CC0",
        backgroundBottomLight: "#6EB7E4", backgroundBottomDark: "#165277",
        muffinTopLightLight: "#9ACAE8", muffinTopLightDark: "#9ACAE8",
        muffinTopDarkLight: "#6C8DA2", muffinTopDarkDark: "#84AEC8",
        creamLight: "#FBFDFF", creamDark: "#282B2D",
        wrapperLight: "#F6FBFE", wrapperDark: "#3E4346",
        blueberryNavyLight: "#256E9D", blueberryNavyDark: "#66AAD6",
        pixelBlueLight: "#D65173", pixelBlueDark: "#DD718D",
        blushPinkLight: "#D651A4", blushPinkDark: "#E291C3",
        brownDarkestLight: "#1F2123", brownDarkestDark: "#FCFEFF",
        brownDarkLight: "#42474B", brownDarkDark: "#F9FCFE",
        brownMidLight: "#768188", brownMidDark: "#F3FAFE",
        sparkleCreamLight: "#F9FCFE", sparkleCreamDark: "#F9FCFE",
        shadowLight: "#35393C", shadowDark: "#000000"
    )

    static let proGoldVip = MuffinThemeDefinition(
        id: "pro-gold-vip", name: "Gold VIP", iconId: "pro-gold-vip",
        backgroundTopLight: "#F8C522", backgroundTopDark: "#7B5F04",
        backgroundBottomLight: "#B47C17", backgroundBottomDark: "#4C3409",
        muffinTopLightLight: "#F7CD61", muffinTopLightDark: "#F7CD61",
        muffinTopDarkLight: "#AD9044", muffinTopDarkDark: "#D4B053",
        creamLight: "#FDF7EA", creamDark: "#291F0A",
        wrapperLight: "#FAEDCD", wrapperDark: "#3F3110",
        blueberryNavyLight: "#999D25", blueberryNavyDark: "#D2D666",
        pixelBlueLight: "#A94519", pixelBlueDark: "#D68866",
        blushPinkLight: "#D6A94F", blushPinkDark: "#D6B166",
        brownDarkestLight: "#211906", brownDarkestDark: "#FEFAF0",
        brownDarkLight: "#47350E", brownDarkDark: "#FCF2DB",
        brownMidLight: "#7F6019", brownMidDark: "#F9E6BC",
        sparkleCreamLight: "#FFFCF6", sparkleCreamDark: "#FFFCF6",
        shadowLight: "#392B0B", shadowDark: "#000000"
    )

    static let proHolographic = MuffinThemeDefinition(
        id: "pro-holographic", name: "Holographic", iconId: "pro-holographic",
        backgroundTopLight: "#E3B3E8", backgroundTopDark: "#842A8E",
        backgroundBottomLight: "#7047E1", backgroundBottomDark: "#29116B",
        muffinTopLightLight: "#ACEEE8", muffinTopLightDark: "#ACEEE8",
        muffinTopDarkLight: "#78A7A2", muffinTopDarkDark: "#94CDC8",
        creamLight: "#F6FCFE", creamDark: "#1F272B",
        wrapperLight: "#EAF7FC", wrapperDark: "#303D43",
        blueberryNavyLight: "#25A093", blueberryNavyDark: "#66D6CB",
        pixelBlueLight: "#BA51D6", pixelBlueDark: "#DAA5E9",
        blushPinkLight: "#8951D6", blushPinkDark: "#C2A6E7",
        brownDarkestLight: "#181F22", brownDarkestDark: "#F9FDFE",
        brownDarkLight: "#324249", brownDarkDark: "#F0F9FD",
        brownMidLight: "#5B7783", brownMidDark: "#E3F4FB",
        sparkleCreamLight: "#FAFEFE", sparkleCreamDark: "#FAFEFE",
        shadowLight: "#28353A", shadowDark: "#000000"
    )

    static let progressPride = MuffinThemeDefinition(
        id: "progress-pride", name: "Progress Pride", iconId: "progress-pride",
        backgroundTopLight: "#C4BBC0", backgroundTopDark: "#5C5156",
        backgroundBottomLight: "#9149CB", backgroundBottomDark: "#3D195A",
        muffinTopLightLight: "#DC7B66", muffinTopLightDark: "#DC7B66",
        muffinTopDarkLight: "#9A5647", muffinTopDarkDark: "#BD6A58",
        creamLight: "#FFFBF2", creamDark: "#2C2619",
        wrapperLight: "#FFF5E1", wrapperDark: "#453B26",
        blueberryNavyLight: "#9D3A25", blueberryNavyDark: "#D67A66",
        pixelBlueLight: "#6E51D6", pixelBlueDark: "#8C77DB",
        blushPinkLight: "#9F51D6", blushPinkDark: "#C193E2",
        brownDarkestLight: "#231E12", brownDarkestDark: "#FFFCF6",
        brownDarkLight: "#4C4027", brownDarkDark: "#FFF8EA",
        brownMidLight: "#897346", brownMidDark: "#FEF2D7",
        sparkleCreamLight: "#FDF7F6", sparkleCreamDark: "#FDF7F6",
        shadowLight: "#3D331F", shadowDark: "#000000"
    )

    static let pumpkinSpice = MuffinThemeDefinition(
        id: "pumpkin-spice", name: "Pumpkin Spice", iconId: "pumpkin-spice",
        backgroundTopLight: "#E5B496", backgroundTopDark: "#894921",
        backgroundBottomLight: "#D17440", backgroundBottomDark: "#5C2F16",
        muffinTopLightLight: "#C16D38", muffinTopLightDark: "#C16D38",
        muffinTopDarkLight: "#874C27", muffinTopDarkDark: "#A65E30",
        creamLight: "#FDF9F4", creamDark: "#29221B",
        wrapperLight: "#F9F0E5", wrapperDark: "#40352B",
        blueberryNavyLight: "#9D7C25", blueberryNavyDark: "#D6B866",
        pixelBlueLight: "#9D2525", pixelBlueDark: "#D66667",
        blushPinkLight: "#D37743", blushPinkDark: "#D68E66",
        brownDarkestLight: "#201B15", brownDarkestDark: "#FDFBF7",
        brownDarkLight: "#46392C", brownDarkDark: "#FBF4ED",
        brownMidLight: "#7D674F", brownMidDark: "#F8EBDC",
        sparkleCreamLight: "#FBF6F3", sparkleCreamDark: "#FBF6F3",
        shadowLight: "#382E23", shadowDark: "#000000"
    )

    static let rainbowPride = MuffinThemeDefinition(
        id: "rainbow-pride", name: "Rainbow Pride", iconId: "rainbow-pride",
        backgroundTopLight: "#FF7D4B", backgroundTopDark: "#952900",
        backgroundBottomLight: "#0700EF", backgroundBottomDark: "#030063",
        muffinTopLightLight: "#CBE36A", muffinTopLightDark: "#CBE36A",
        muffinTopDarkLight: "#8E9F4A", muffinTopDarkDark: "#AFC35B",
        creamLight: "#FFF9ED", creamDark: "#2C230F",
        wrapperLight: "#FFF1D4", wrapperDark: "#443618",
        blueberryNavyLight: "#869D25", blueberryNavyDark: "#C1D666",
        pixelBlueLight: "#50D86B", pixelBlueDark: "#87E49A",
        blushPinkLight: "#68D651", blushPinkDark: "#AFE7A4",
        brownDarkestLight: "#241B0B", brownDarkestDark: "#FFFBF2",
        brownDarkLight: "#4D3B17", brownDarkDark: "#FFF5E0",
        brownMidLight: "#8A6A28", brownMidDark: "#FFECC5",
        sparkleCreamLight: "#FCFDF6", sparkleCreamDark: "#FCFDF6",
        shadowLight: "#3D2F12", shadowDark: "#000000"
    )

    static let retro = MuffinThemeDefinition(
        id: "retro", name: "Retro Console", iconId: "retro",
        backgroundTopLight: "#C0B0D6", backgroundTopDark: "#533D72",
        backgroundBottomLight: "#7A55C4", backgroundBottomDark: "#311E57",
        muffinTopLightLight: "#422869", muffinTopLightDark: "#422869",
        muffinTopDarkLight: "#2E1C4A", muffinTopDarkDark: "#39225A",
        creamLight: "#FCF9F6", creamDark: "#28241E",
        wrapperLight: "#F8F2E9", wrapperDark: "#3E382F",
        blueberryNavyLight: "#54259D", blueberryNavyDark: "#9266D6",
        pixelBlueLight: "#AF3F29", pixelBlueDark: "#D67966",
        blushPinkLight: "#D69851", blushPinkDark: "#D6A266",
        brownDarkestLight: "#201C17", brownDarkestDark: "#FDFBF9",
        brownDarkLight: "#443C31", brownDarkDark: "#FAF5EF",
        brownMidLight: "#7B6B58", brownMidDark: "#F6EDE2",
        sparkleCreamLight: "#F4F2F6", sparkleCreamDark: "#F4F2F6",
        shadowLight: "#363027", shadowDark: "#000000"
    )

    static let spookyHalloween = MuffinThemeDefinition(
        id: "spooky-halloween", name: "Spooky Halloween", iconId: "spooky-halloween",
        backgroundTopLight: "#643286", backgroundTopDark: "#2D173C",
        backgroundBottomLight: "#461F65", backgroundBottomDark: "#1E0D2B",
        muffinTopLightLight: "#351C47", muffinTopLightDark: "#351C47",
        muffinTopDarkLight: "#251432", muffinTopDarkDark: "#2E183D",
        creamLight: "#F2EDEB", creamDark: "#170F0B",
        wrapperLight: "#E1D5CF", wrapperDark: "#231711",
        blueberryNavyLight: "#6A259D", blueberryNavyDark: "#A766D6",
        pixelBlueLight: "#D68751", pixelBlueDark: "#E7BEA3",
        blushPinkLight: "#D65651", blushPinkDark: "#E7A9A6",
        brownDarkestLight: "#120B08", brownDarkestDark: "#F6F3F1",
        brownDarkLight: "#271811", brownDarkDark: "#EAE1DD",
        brownMidLight: "#462B1E", brownMidDark: "#D7C7BF",
        sparkleCreamLight: "#F3F1F4", sparkleCreamDark: "#F3F1F4",
        shadowLight: "#1F130D", shadowDark: "#000000"
    )

    static let strawberry = MuffinThemeDefinition(
        id: "strawberry", name: "Strawberry", iconId: "strawberry",
        backgroundTopLight: "#FFBFD1", backgroundTopDark: "#C90037",
        backgroundBottomLight: "#FF4276", backgroundBottomDark: "#860025",
        muffinTopLightLight: "#F8E7DB", muffinTopLightDark: "#F8E7DB",
        muffinTopDarkLight: "#AEA299", muffinTopDarkDark: "#D5C7BC",
        creamLight: "#FFF9FA", creamDark: "#2D2326",
        wrapperLight: "#FFF0F4", wrapperDark: "#46373B",
        blueberryNavyLight: "#B6602B", blueberryNavyDark: "#DA9B74",
        pixelBlueLight: "#7AD651", pixelBlueDark: "#92DD71",
        blushPinkLight: "#51D65A", blushPinkDark: "#91E296",
        brownDarkestLight: "#241B1D", brownDarkestDark: "#FFFBFC",
        brownDarkLight: "#4D393F", brownDarkDark: "#FFF4F7",
        brownMidLight: "#8A6771", brownMidDark: "#FFEBF0",
        sparkleCreamLight: "#FFFEFD", sparkleCreamDark: "#FFFEFD",
        shadowLight: "#3D2E32", shadowDark: "#000000"
    )

    static let summerBeach = MuffinThemeDefinition(
        id: "summer-beach", name: "Summer Beach", iconId: "summer-beach",
        backgroundTopLight: "#29ABAA", backgroundTopDark: "#124D4C",
        backgroundBottomLight: "#1B6F7E", backgroundBottomDark: "#0B2F35",
        muffinTopLightLight: "#4DBDC6", muffinTopLightDark: "#4DBDC6",
        muffinTopDarkLight: "#36848B", muffinTopDarkDark: "#42A3AA",
        creamLight: "#EAF5F7", creamDark: "#091A1D",
        wrapperLight: "#CCE6EB", wrapperDark: "#0E292E",
        blueberryNavyLight: "#25949D", blueberryNavyDark: "#66CED6",
        pixelBlueLight: "#C8662F", pixelBlueDark: "#D68E66",
        blushPinkLight: "#D6B251", blushPinkDark: "#D9BD72",
        brownDarkestLight: "#061518", brownDarkestDark: "#F0F8F9",
        brownDarkLight: "#0C2E33", brownDarkDark: "#DBEDF1",
        brownMidLight: "#16525C", brownMidDark: "#BBDEE4",
        sparkleCreamLight: "#F4FBFC", sparkleCreamDark: "#F4FBFC",
        shadowLight: "#0A2429", shadowDark: "#000000"
    )

    static let transgenderPride = MuffinThemeDefinition(
        id: "transgender-pride", name: "Transgender Pride", iconId: "transgender-pride",
        backgroundTopLight: "#5BCEFA", backgroundTopDark: "#056D94",
        backgroundBottomLight: "#07AEEE", backgroundBottomDark: "#034964",
        muffinTopLightLight: "#F3A9B8", muffinTopLightDark: "#F3A9B8",
        muffinTopDarkLight: "#AA7681", muffinTopDarkDark: "#D1919E",
        creamLight: "#EFFAFE", creamDark: "#12242B",
        wrapperLight: "#D8F3FE", wrapperDark: "#1C3943",
        blueberryNavyLight: "#A0263D", blueberryNavyDark: "#D6667B",
        pixelBlueLight: "#51A3D6", pixelBlueDark: "#A6CEE7",
        blushPinkLight: "#5173D6", blushPinkDark: "#A6B7E7",
        brownDarkestLight: "#0D1D23", brownDarkestDark: "#F4FCFF",
        brownDarkLight: "#1B3E4B", brownDarkDark: "#E3F7FE",
        brownMidLight: "#316F87", brownMidDark: "#CBEFFD",
        sparkleCreamLight: "#FEFAFB", sparkleCreamDark: "#FEFAFB",
        shadowLight: "#16313C", shadowDark: "#000000"
    )

    static let all: [MuffinThemeDefinition] = [
        bakery, adhdAwareness, audhdAwareness, autismAwareness, bisexualPride, blueberryBlast, dark, disabilityPride, doubleChocolate, equality, fixTheWorld, galaxySpace, happy, holidayFrost, lemonZest, lesbianPride, mentalHealthPride, mintMatcha, neonCyber, nonbinaryPride, proDiamondIce, proGoldVip, proHolographic, progressPride, pumpkinSpice, rainbowPride, retro, spookyHalloween, strawberry, summerBeach, transgenderPride
    ]
}
