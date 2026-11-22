using System;
using System.Collections.Generic;

namespace ScreenRest
{
    public class Exercise
    {
        public readonly string TitleEn, StepsEn, TitleTl, StepsTl;
        public int Seconds;

        public Exercise(string titleEn, string stepsEn, string titleTl, string stepsTl)
        {
            TitleEn = titleEn; StepsEn = stepsEn;
            TitleTl = titleTl ?? titleEn; StepsTl = stepsTl ?? stepsEn;
        }
        public Exercise(string title, string steps) : this(title, steps, null, null) { }

        /// <summary>Title and steps in the interface language (see L).</summary>
        public string Title { get { return L.Tl ? TitleTl : TitleEn; } }
        public string Steps { get { return L.Tl ? StepsTl : StepsEn; } }

        public Exercise With(int seconds) { var e = new Exercise(TitleEn, StepsEn, TitleTl, StepsTl); e.Seconds = seconds; return e; }

        /// <summary>Copy with an extra paragraph appended in both languages.</summary>
        public Exercise Plus(string en, string tl)
        {
            var e = new Exercise(TitleEn, StepsEn + "\n\n" + en, TitleTl, StepsTl + "\n\n" + tl);
            e.Seconds = Seconds;
            return e;
        }

        /// <summary>File-name key for the demo clip, always from the English title, e.g. "Calf raises" -> "calf_raises".</summary>
        public string Slug
        {
            get
            {
                var sb = new System.Text.StringBuilder();
                foreach (char c in TitleEn.ToLowerInvariant())
                    sb.Append(char.IsLetterOrDigit(c) ? c : '_');
                return System.Text.RegularExpressions.Regex.Replace(sb.ToString(), "_+", "_").Trim('_');
            }
        }

        /// <summary>Path of the demo animation next to the exe, or null if there isn't one.</summary>
        public string MediaPath { get { return Media(".gif"); } }

        /// <summary>Path of the spoken voice-over (PCM .wav) next to the exe, or null.</summary>
        public string AudioPath { get { return Media(".wav"); } }

        string Media(string ext)
        {
            string exeDir = System.IO.Path.GetDirectoryName(typeof(Exercise).Assembly.Location);
            string p = System.IO.Path.Combine(System.IO.Path.Combine(exeDir, "media"), Slug + ext);
            return System.IO.File.Exists(p) ? p : null;
        }
    }

    /// <summary>Eye exercises for short breaks, and blood-flow / posture moves for stand-up breaks.</summary>
    public static class Exercises
    {
        public static readonly Exercise[] Eye =
        {
            new Exercise("Look far away",
                "Find something at least 6 metres (20 feet) away: a window, a hallway, the far wall.\n" +
                "Let your eyes go soft and relax. That's the 20-20-20 rule.",
                "Tumingin sa malayo",
                "Maghanap ng bagay na hindi bababa sa 6 na metro (20 talampakan) ang layo: bintana, pasilyo, o ang dulong pader.\n" +
                "Hayaang lumambot at mag-relax ang iyong mga mata. Iyan ang 20-20-20 rule."),
            new Exercise("Slow blinks",
                "Close your eyes fully, then open them. Do it slowly, 10 times.\n" +
                "Staring at a screen makes you blink about half as often, so your eyes dry out and blur.",
                "Dahan-dahang pagkurap",
                "Ipikit nang buo ang mga mata, saka idilat. Gawin nang dahan-dahan, 10 beses.\n" +
                "Kapag nakatitig sa screen, halos kalahati lang ang dalas ng pagkurap, kaya natutuyo at lumalabo ang mata."),
            new Exercise("Palming",
                "Rub your palms together until warm, then cup them over your closed eyes.\n" +
                "Don't press. Breathe slowly and enjoy the darkness.",
                "Palming",
                "Pagkiskisin ang mga palad hanggang uminit, saka itakip sa nakapikit na mga mata.\n" +
                "Huwag diinan. Huminga nang dahan-dahan at damhin ang dilim."),
            new Exercise("Near and far focus",
                "Hold your thumb about 25 cm from your face and focus on it.\n" +
                "Then focus on something far away. Switch every 3 seconds.",
                "Malapit at malayong tingin",
                "Itapat ang hinlalaki mga 25 cm mula sa mukha at tumutok dito.\n" +
                "Pagkatapos, tumutok sa isang bagay sa malayo. Magpalit tuwing 3 segundo."),
            new Exercise("Eye circles",
                "Without moving your head, slowly look up, then right, down, and left.\n" +
                "Make 3 slow circles, then reverse direction.",
                "Pag-ikot ng mata",
                "Nang hindi gumagalaw ang ulo, dahan-dahang tumingin pataas, pakanan, pababa, at pakaliwa.\n" +
                "Gumawa ng 3 mabagal na ikot, saka baligtarin ang direksyon."),
            new Exercise("Look out and breathe",
                "Look at the farthest point you can see.\n" +
                "At the same time, roll your shoulders back 5 times and take 3 deep breaths.",
                "Tumanaw at huminga",
                "Tumingin sa pinakamalayong bahagi na kaya mong makita.\n" +
                "Kasabay nito, iikot paatras ang mga balikat nang 5 beses at huminga nang malalim nang 3 beses."),
        };

        // Small body cue added under each eye break, so short breaks help circulation too. {English, Tagalog}
        public static readonly string[][] MicroBodyCues =
        {
            new[] { "While you're at it: drop your shoulders away from your ears.",
                    "Isabay na rin: ibaba ang mga balikat, palayo sa tainga." },
            new[] { "While you're at it: point and flex both feet 10 times under the desk.",
                    "Isabay na rin: itulis at ibaluktot ang dalawang paa nang 10 beses sa ilalim ng mesa." },
            new[] { "While you're at it: sit tall, chin slightly tucked, feet flat on the floor.",
                    "Isabay na rin: umupo nang tuwid, bahagyang nakababa ang baba, nakalapat ang paa sa sahig." },
            new[] { "While you're at it: squeeze your shoulder blades together for 5 seconds.",
                    "Isabay na rin: pagdikitin ang mga talim ng balikat (shoulder blades) nang 5 segundo." },
            new[] { "While you're at it: unclench your jaw and relax your hands.",
                    "Isabay na rin: luwagan ang panga at i-relax ang mga kamay." },
        };

        public static readonly Exercise StandUp = new Exercise("Stand up!",
            "Push your chair back and stand up tall. Shake out your arms and legs.\n" +
            "Look away from the screen. This whole break happens on your feet.",
            "Tumayo!",
            "Iurong ang upuan at tumayo nang tuwid. Ipagpag ang mga braso at binti.\n" +
            "Tumingin palayo sa screen. Nakatayo ka sa buong break na ito.");

        public static readonly Exercise[] Body =
        {
            new Exercise("Calf raises",
                "Rise up onto your toes, hold for 1 second, and lower slowly. Repeat 15 times.\n" +
                "Your calf muscles pump blood back up from your legs, so they work like a second heart.",
                "Pagtingkayad",
                "Tumingkayad, hawakan nang 1 segundo, at ibaba nang dahan-dahan. Ulitin nang 15 beses.\n" +
                "Ang kalamnan ng binti ang nagbobomba ng dugo pabalik mula sa paa, kaya para itong pangalawang puso."),
            new Exercise("Neck side stretch",
                "Gently tilt your right ear toward your right shoulder and hold for 10 seconds.\n" +
                "Switch sides. Then slowly look over each shoulder. Never force it.",
                "Pag-unat ng leeg sa gilid",
                "Dahan-dahang ikiling ang kanang tainga papunta sa kanang balikat at hawakan nang 10 segundo.\n" +
                "Magpalit ng gilid. Saka dahan-dahang lumingon sa bawat balikat. Huwag pilitin."),
            new Exercise("Shoulder rolls",
                "Roll both shoulders up, back and down 10 times.\n" +
                "Then squeeze your shoulder blades together and hold for 5 seconds, 3 times.",
                "Pag-ikot ng balikat",
                "Iikot ang dalawang balikat pataas, paatras at pababa nang 10 beses.\n" +
                "Pagkatapos, pagdikitin ang mga shoulder blade at hawakan nang 5 segundo, 3 beses."),
            new Exercise("Chest opener",
                "Clasp your hands behind your back, straighten your arms, and lift them a little.\n" +
                "Open your chest and look slightly up. Breathe deeply. This undoes the hunch.",
                "Pagbukas ng dibdib",
                "Pagdaupin ang mga kamay sa likod, ituwid ang mga braso, at bahagyang iangat.\n" +
                "Ibuka ang dibdib at bahagyang tumingala. Huminga nang malalim. Itinutuwid nito ang pagkakuba."),
            new Exercise("March in place",
                "March on the spot, lifting your knees high and swinging your arms.\n" +
                "Or walk a lap around the office. Get your heart rate up a little.",
                "Magmartsa sa puwesto",
                "Magmartsa sa kinatatayuan, itaas ang mga tuhod at iwasiwas ang mga braso.\n" +
                "O maglakad nang isang ikot sa opisina. Pabilisin nang kaunti ang tibok ng puso."),
            new Exercise("Standing back bend",
                "Put your hands on your lower back, fingers pointing down.\n" +
                "Gently lean back and look up. Hold for 3 seconds. Repeat 5 times.",
                "Pag-arko ng likod nang nakatayo",
                "Ilagay ang mga kamay sa ibabang bahagi ng likod, nakaturo pababa ang mga daliri.\n" +
                "Dahan-dahang sumandal paatras at tumingala. Hawakan nang 3 segundo. Ulitin nang 5 beses."),
            new Exercise("Chair squats",
                "Stand in front of your chair with feet hip-width apart.\n" +
                "Sit back until you just touch the seat, then stand up. Repeat 10 times, slowly.",
                "Squat sa upuan",
                "Tumayo sa harap ng upuan, magkahiwalay ang mga paa na kasinlapad ng balakang.\n" +
                "Umupo paatras hanggang dumampi lang sa upuan, saka tumayo. Ulitin nang 10 beses, dahan-dahan."),
            new Exercise("Wrist and forearm stretch",
                "Arm straight out, palm up. With your other hand, gently pull your fingers down for 15 seconds.\n" +
                "Flip your palm down and repeat. Do both arms.",
                "Pag-unat ng pulso at bisig",
                "Iunat ang braso pasulong, nakaharap pataas ang palad. Gamit ang kabilang kamay, dahan-dahang hilahin pababa ang mga daliri nang 15 segundo.\n" +
                "Ibaligtad pababa ang palad at ulitin. Gawin sa dalawang braso."),
            new Exercise("Hip flexor stretch",
                "Take a big step forward into a gentle lunge, back knee soft.\n" +
                "Tuck your hips under until you feel the front of the back hip stretch. 15 seconds per side.",
                "Pag-unat ng balakang",
                "Humakbang nang malaki pasulong sa banayad na lunge, bahagyang nakabaluktot ang tuhod sa likod.\n" +
                "Ipasok ang balakang hanggang maramdaman ang unat sa harap ng balakang ng paang nasa likod. 15 segundo bawat gilid."),
            new Exercise("Standing twist",
                "Feet planted and arms crossed over your chest.\n" +
                "Slowly rotate your upper body right and hold, then left and hold. 5 times each way.",
                "Pagpihit nang nakatayo",
                "Nakatapak nang matatag ang mga paa at nakakrus ang mga braso sa dibdib.\n" +
                "Dahan-dahang ipihit ang itaas na katawan pakanan at hawakan, saka pakaliwa at hawakan. 5 beses bawat direksyon."),
            new Exercise("Ankle circles",
                "Hold the desk for balance and lift one foot.\n" +
                "Circle the ankle 10 times each way, then switch feet. Good for leg circulation.",
                "Pag-ikot ng bukung-bukong",
                "Humawak sa mesa para sa balanse at iangat ang isang paa.\n" +
                "Iikot ang bukung-bukong nang 10 beses sa bawat direksyon, saka magpalit ng paa. Maganda para sa daloy ng dugo sa binti."),
            new Exercise("Overhead reach",
                "Interlace your fingers and push your palms up toward the ceiling.\n" +
                "Reach tall, then lean gently left and right. Breathe out as you stretch.",
                "Pag-abot pataas",
                "Pagsalikupin ang mga daliri at itulak ang mga palad pataas sa kisame.\n" +
                "Umabot nang mataas, saka dahan-dahang humilig pakaliwa at pakanan. Huminga palabas habang nag-uunat."),
        };

        public static readonly Exercise WalkWater = new Exercise("Walk and hydrate",
            "Walk to get a glass of water, or refill your bottle.\n" +
            "Staying hydrated helps with tiredness and dry eyes. Keep looking at things far away.",
            "Maglakad at uminom ng tubig",
            "Maglakad para kumuha ng isang basong tubig, o punuin ang iyong bote.\n" +
            "Ang sapat na tubig ay nakakatulong laban sa pagod at tuyong mata. Patuloy na tumingin sa malalayong bagay.");

        static readonly Random rng = new Random();
        static int eyeIdx = rng.Next(Eye.Length);
        static int cueIdx = rng.Next(MicroBodyCues.Length);
        static int bodyIdx = rng.Next(Body.Length);

        public static List<Exercise> EyeBreak(int seconds)
        {
            var cue = MicroBodyCues[cueIdx++ % MicroBodyCues.Length];
            var e = Eye[eyeIdx++ % Eye.Length].With(seconds).Plus(cue[0], cue[1]);
            return new List<Exercise> { e };
        }

        /// <summary>Stand up, then rotating exercises (about 50 s each), then walk and drink water.</summary>
        public static List<Exercise> StretchRoutine(int totalSec)
        {
            var list = new List<Exercise>();
            int first = Math.Min(20, totalSec);
            list.Add(StandUp.With(first));
            int remaining = totalSec - first;
            int last = remaining >= 90 ? 40 : 0;
            remaining -= last;
            while (remaining > 0)
            {
                int d = Math.Min(remaining, 50);
                if (remaining - d > 0 && remaining - d < 20) d = remaining; // don't leave a tiny tail
                list.Add(Body[bodyIdx++ % Body.Length].With(d));
                remaining -= d;
            }
            if (last > 0) list.Add(WalkWater.With(last));
            return list;
        }
    }
}
