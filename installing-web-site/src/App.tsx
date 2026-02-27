import { Navbar } from '@/components/Navbar'
import { HeroSection } from '@/components/sections/HeroSection'
import { HowItWorksSection } from '@/components/sections/HowItWorksSection'
import { FeaturesSection } from '@/components/sections/FeaturesSection'
import { ScreenshotsSection } from '@/components/sections/ScreenshotsSection'
import { DownloadSection } from '@/components/sections/DownloadSection'
import { FaqSection } from '@/components/sections/FaqSection'
import { FooterSection } from '@/components/sections/FooterSection'

function App() {
  return (
    <div className="min-h-screen bg-[#080b14] text-white font-sans">
      <Navbar />
      <main>
        <HeroSection />
        <HowItWorksSection />
        <FeaturesSection />
        <ScreenshotsSection />
        <DownloadSection />
        <FaqSection />
      </main>
      <FooterSection />
    </div>
  )
}

export default App
