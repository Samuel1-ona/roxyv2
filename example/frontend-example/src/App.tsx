import { useState, useEffect } from 'react';
import { useConnect } from '@stacks/connect-react';
import {
  Cl,
  PostConditionMode
} from '@stacks/transactions';
import { Trophy, MousePointer2, Save, Swords, User as UserIcon, LogOut } from 'lucide-react';
import { userSession, authenticate, logout, network } from './stacks';

const CLICK_GAME_CONTRACT = 'ST2N04CYE3CQ1S354MZX4KHYJYD4QW25ZW37GQY7J.click-game';
const ROXY_SDK_CONTRACT = 'STVAH96MR73TP2FZG2W4X220MEB4NEMJHPMVYQNS.Roxy';

function App() {
  const { doContractCall } = useConnect();
  const [score, setScore] = useState(0);
  const [onChainScore] = useState(0);
  const [campaignId] = useState(1);
  const [isSyncing, setIsSyncing] = useState(false);
  const [userData, setUserData] = useState<any>(null);

  useEffect(() => {
    if (userSession.isUserSignedIn()) {
      setUserData(userSession.loadUserData());
    }
  }, []);

  const handleClick = async () => {
    if (!userSession.isUserSignedIn()) {
      authenticate();
      return;
    }

    setScore(s => s + 1);

    await doContractCall({
      contractAddress: CLICK_GAME_CONTRACT.split('.')[0],
      contractName: CLICK_GAME_CONTRACT.split('.')[1],
      functionName: 'click',
      functionArgs: [Cl.uint(campaignId)],
      network,
      postConditionMode: PostConditionMode.Allow,
      onFinish: (data: any) => {
        console.log('Transaction sent:', data);
      },
      onCancel: () => console.log('Transaction cancelled'),
    });
  };

  const syncScore = async () => {
    if (!userData) return;
    setIsSyncing(true);

    // Addresses for trait arguments
    const sdkAddress = ROXY_SDK_CONTRACT.split('.')[0];
    const sdkName = ROXY_SDK_CONTRACT.split('.')[1];
    const gameAddress = CLICK_GAME_CONTRACT.split('.')[0];
    const gameName = CLICK_GAME_CONTRACT.split('.')[1];

    await doContractCall({
      contractAddress: gameAddress,
      contractName: gameName,
      functionName: 'sdk-sync-score',
      functionArgs: [
        Cl.contractPrincipal(sdkAddress, sdkName),
        Cl.uint(campaignId),
        Cl.standardPrincipal(userData.profile.stxAddress.testnet || userData.profile.stxAddress.mainnet),
        Cl.contractPrincipal(gameAddress, gameName)
      ],
      network,
      postConditionMode: PostConditionMode.Allow,
      onFinish: () => setIsSyncing(false),
      onCancel: () => setIsSyncing(false),
    });
  };

  const setUsername = async (name: string) => {
    if (!userData) return;

    const sdkAddress = ROXY_SDK_CONTRACT.split('.')[0];
    const sdkName = ROXY_SDK_CONTRACT.split('.')[1];
    const gameAddress = CLICK_GAME_CONTRACT.split('.')[0];
    const gameName = CLICK_GAME_CONTRACT.split('.')[1];

    console.log('Setting username:', name);
    console.log('Using SDK:', sdkAddress, sdkName);
    console.log('Using Game:', gameAddress, gameName);

    await doContractCall({
      contractAddress: gameAddress,
      contractName: gameName,
      functionName: 'sdk-set-username',
      functionArgs: [
        Cl.contractPrincipal(sdkAddress, sdkName),
        Cl.stringAscii(name)
      ],
      network,
      postConditionMode: PostConditionMode.Allow,
      onFinish: (data: any) => {
        console.log('Set Username Transaction sent:', data);
      },
      onCancel: () => console.log('Transaction cancelled'),
    });
  };

  if (!userSession.isUserSignedIn()) {
    return (
      <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-[#0a0a0f] to-[#1a1a2e]">
        <div className="glass-panel p-8 max-w-md w-full text-center space-y-6 premium-card">
          <div className="w-20 h-20 bg-accent-primary/20 rounded-full flex items-center justify-center mx-auto mb-4">
            <Trophy className="w-10 h-10 text-[#7c4dff]" />
          </div>
          <h1 className="text-4xl font-bold tracking-tight text-white">Roxy Clicker</h1>
          <p className="text-text-muted">Enter the arena on Bitcoin L2 and compete for the top spot.</p>
          <button onClick={authenticate} className="btn-primary w-full text-lg">
            Connect Wallet
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen p-6 max-w-6xl mx-auto space-y-8">
      {/* Header */}
      <header className="flex justify-between items-center glass-panel p-4 px-8">
        <div className="flex items-center gap-3">
          <Trophy className="text-[#00e5ff] w-6 h-6" />
          <span className="text-xl font-bold">Roxy Clicker</span>
        </div>
        <div className="flex items-center gap-4">
          <div className="text-right hidden sm:block">
            <div className="text-sm text-text-muted">Player</div>
            <div className="text-sm font-mono truncate max-w-[150px]">
              {userData?.profile.stxAddress.testnet || userData?.profile.stxAddress.mainnet}
            </div>
          </div>
          <button onClick={logout} className="p-2 hover:bg-white/10 rounded-full transition-colors">
            <LogOut className="w-5 h-5 text-red-400" />
          </button>
        </div>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Left Column: Stats & Identity */}
        <div className="space-y-6">
          <div className="glass-panel p-6 space-y-4 premium-card">
            <div className="flex items-center gap-2 text-[#7c4dff] font-semibold">
              <UserIcon className="w-5 h-5" />
              <span>Gamer Identity</span>
            </div>
            <div className="space-y-2">
              <input
                type="text"
                placeholder="Set Username"
                className="w-full bg-[#1a1a2e] border border-glass-border p-3 rounded-xl focus:outline-none focus:border-[#7c4dff] text-white"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') setUsername(e.currentTarget.value);
                }}
              />
              <p className="text-xs text-text-muted">Press Enter to set on-chain.</p>
            </div>
          </div>

          <div className="glass-panel p-6 space-y-4 premium-card">
            <div className="flex items-center gap-2 text-[#00e5ff] font-semibold">
              <Save className="w-5 h-5" />
              <span>Sync Progress</span>
            </div>
            <div className="flex flex-col gap-2">
              <div className="flex justify-between text-sm">
                <span className="text-text-muted">Local Clicks</span>
                <span className="font-bold text-white">{score}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-text-muted">On-Chain Score</span>
                <span className="font-bold text-white">{onChainScore}</span>
              </div>
              <button
                onClick={syncScore}
                disabled={isSyncing}
                className="btn-primary mt-2 flex items-center justify-center gap-2"
              >
                {isSyncing ? 'Syncing...' : (
                  <>
                    <Save className="w-4 h-4" />
                    Level Up On-Chain
                  </>
                )}
              </button>
            </div>
          </div>
        </div>

        {/* Center Column: The Primary Interaction */}
        <div className="lg:col-span-1 flex flex-col items-center justify-center space-y-8 py-12">
          <button
            onClick={handleClick}
            className="w-64 h-64 bg-gradient-to-tr from-[#7c4dff] to-[#00e5ff] rounded-full flex items-center justify-center premium-card glow-active shadow-[0_0_50px_rgba(124,77,255,0.4)] group active:scale-95 transition-all duration-75"
          >
            <div className="text-center group-hover:scale-110 transition-transform">
              <MousePointer2 className="w-16 h-16 text-white mx-auto mb-2" />
              <div className="text-3xl font-black text-white uppercase tracking-widest">CLICK</div>
            </div>
          </button>
          <div className="text-center">
            <div className="text-5xl font-black text-white mb-2">{score}</div>
            <div className="text-text-muted uppercase tracking-arena font-semibold text-sm">Total Power</div>
          </div>
        </div>

        {/* Right Column: Arena & Battleground */}
        <div className="space-y-6">
          <div className="glass-panel p-6 space-y-4 premium-card">
            <div className="flex items-center gap-2 text-red-500 font-semibold">
              <Swords className="w-5 h-5" />
              <span>Arena Battles</span>
            </div>
            <div className="space-y-3">
              <div className="p-4 bg-white/5 rounded-xl border border-glass-border">
                <div className="text-sm font-bold mb-1 text-white">Arena Match #42</div>
                <div className="text-xs text-text-muted mb-3">Goal: 5,000 Clicks</div>
                <div className="grid grid-cols-2 gap-2">
                  <button className="bg-green-500/20 text-green-400 p-2 rounded-lg text-xs font-bold hover:bg-green-500/30 transition-colors">VOTE YES</button>
                  <button className="bg-red-500/20 text-red-400 p-2 rounded-lg text-xs font-bold hover:bg-red-500/30 transition-colors">VOTE NO</button>
                </div>
              </div>
              <button className="w-full p-3 bg-white/5 hover:bg-white/10 border border-dashed border-glass-border rounded-xl text-xs font-bold uppercase tracking-wider text-text-muted transition-colors">
                Create Match (+ Arena Fee)
              </button>
            </div>
          </div>
        </div>
      </div>

      <footer className="text-center py-12 text-text-muted text-xs space-y-2">
        <p>Roxy SDK v2.3.0 | Powered by Stacks | Secured by Bitcoin</p>
        <p className="opacity-50 font-mono">Arena: {campaignId} | SDK: {ROXY_SDK_CONTRACT}</p>
      </footer>
    </div>
  );
}

export default App;
