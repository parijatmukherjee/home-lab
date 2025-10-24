import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";

interface LocationData {
  ip: string;
  city: string;
  region: string;
  country: string;
}

const LoginTerminal = () => {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [isProcessing, setIsProcessing] = useState(false);
  const [locationData, setLocationData] = useState<LocationData | null>(null);
  const { toast } = useToast();
  const navigate = useNavigate();

  useEffect(() => {
    // Fetch user's real IP and location
    const fetchLocationData = async () => {
      try {
        const response = await fetch("https://ipapi.co/json/");
        const data = await response.json();
        setLocationData({
          ip: data.ip,
          city: data.city,
          region: data.region,
          country: data.country_name,
        });
      } catch (error) {
        console.error("Failed to fetch location data:", error);
        // Fallback to just showing a placeholder
        setLocationData({
          ip: "UNKNOWN",
          city: "UNKNOWN",
          region: "UNKNOWN",
          country: "UNKNOWN",
        });
      }
    };

    fetchLocationData();
  }, []);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!username || !password) {
      toast({
        title: "ERROR",
        description: "Both fields are required. Obviously.",
        variant: "destructive",
      });
      return;
    }

    setIsProcessing(true);

    try {
      const response = await fetch("/api/auth", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ username, password }),
      });

      const data = await response.json();

      if (data.success) {
        sessionStorage.setItem("authenticated", "true");
        toast({
          title: "ACCESS GRANTED",
          description: "Welcome to the Mohjave Core Systems...",
        });
        setTimeout(() => {
          navigate("/dashboard");
        }, 500);
      } else {
        toast({
          title: "ACCESS DENIED",
          description: data.message || "Invalid credentials. Try again.",
          variant: "destructive",
        });
        setIsProcessing(false);
      }
    } catch (error) {
      toast({
        title: "CONNECTION ERROR",
        description: "Failed to connect to authentication service.",
        variant: "destructive",
      });
      setIsProcessing(false);
    }
  };

  return (
    <div className="relative border-2 border-primary p-8 max-w-md w-full backdrop-blur-sm bg-card/50">
      {/* Scan line effect */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute w-full h-1 bg-primary/30 blur-sm animate-[scan-line_4s_linear_infinite]" />
      </div>

      <div className="relative z-10">
        <div className="mb-6">
          <p className="text-primary matrix-text mb-2">&gt; SYSTEM ACCESS TERMINAL</p>
          <p className="text-muted-foreground text-sm mb-1">&gt; Connection: SECURE</p>
          <p className="text-muted-foreground text-sm mb-1">
            &gt; Location: {locationData ? `${locationData.city}, ${locationData.region}, ${locationData.country}` : "Detecting..."}
          </p>
          <p className="text-muted-foreground text-sm mb-1">
            &gt; Your IP has been logged: {locationData ? locationData.ip : "Detecting..."}
          </p>
          <p className="text-warning text-sm glitch-effect">&gt; WARNING: Unauthorized access detected</p>
        </div>

        <form onSubmit={handleLogin} className="space-y-4">
          <div>
            <label className="text-foreground text-sm mb-2 block">&gt; Username:</label>
            <Input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="bg-background border-primary text-primary focus:ring-primary font-mono"
              placeholder="Enter username..."
              disabled={isProcessing}
            />
          </div>

          <div>
            <label className="text-foreground text-sm mb-2 block">&gt; Password:</label>
            <Input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="bg-background border-primary text-primary focus:ring-primary font-mono"
              placeholder="Enter password..."
              disabled={isProcessing}
            />
          </div>

          <Button
            type="submit"
            className="w-full bg-primary hover:bg-primary/80 text-primary-foreground font-mono font-bold border border-primary shadow-lg shadow-primary/50 transition-all"
            disabled={isProcessing}
          >
            {isProcessing ? "> PROCESSING..." : "> INITIATE ACCESS"}
          </Button>
        </form>

        <div className="mt-6 text-xs text-muted-foreground space-y-1">
          <p>&gt; Tip: We know you're here</p>
          <p>&gt; Tip: We're watching</p>
          <p>&gt; Tip: Turn back now</p>
        </div>
      </div>
    </div>
  );
};

export default LoginTerminal;
