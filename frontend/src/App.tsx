import { useState, useEffect } from 'react';
import {
  useAccount,
  useChainId,
  useConnect,
  useDisconnect,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
  useBalance,
  useSignMessage,
} from 'wagmi';
import { formatUnits, parseUnits, encodeFunctionData } from 'viem';
import { baseErc20Abi } from './contracts/BaseERC20';
import { tokenBankAbi } from './contracts/TokenBank';
import {
  getAddresses,
} from './contracts/addresses';
import './App.scss';

interface TransferRecord {
  id: number;
  tx_hash: string;
  block_number: number;
  from_address: string;
  to_address: string;
  amount: string;
  timestamp: number;
  created_at: string;
}

function App() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();
  const { data: ethBalance } = useBalance({ address });
  const { signMessageAsync } = useSignMessage();

  const { TOKEN_ADDRESS, TOKEN_BANK_ADDRESS } = getAddresses(chainId);

  const [amount, setAmount] = useState('');
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const [action, setAction] = useState<'approve' | 'deposit' | 'withdraw' | 'eip7702Deposit'>('deposit');
  const [siweAuthed, setSiweAuthed] = useState(false);
  const [siweSigning, setSiweSigning] = useState(false);
  const [transfers, setTransfers] = useState<TransferRecord[]>([]);
  const [transfersLoading, setTransfersLoading] = useState(false);

  // Read token info
  const { data: tokenName } = useReadContract({
    address: TOKEN_ADDRESS,
    abi: baseErc20Abi,
    functionName: 'name',
  });

  const { data: tokenSymbol } = useReadContract({
    address: TOKEN_ADDRESS,
    abi: baseErc20Abi,
    functionName: 'symbol',
  });

  const { data: decimals } = useReadContract({
    address: TOKEN_ADDRESS,
    abi: baseErc20Abi,
    functionName: 'decimals',
  });

  // Read token balance
  const { data: tokenBalance, refetch: refetchTokenBalance } = useReadContract({
    address: TOKEN_ADDRESS,
    abi: baseErc20Abi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  // Read deposit balance
  const { data: depositBalance, refetch: refetchDepositBalance } = useReadContract({
    address: TOKEN_BANK_ADDRESS,
    abi: tokenBankAbi,
    functionName: 'getDepositBalance',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  // Read total bank balance
  const { data: totalBankBalance, refetch: refetchTotalBalance } = useReadContract({
    address: TOKEN_BANK_ADDRESS,
    abi: tokenBankAbi,
    functionName: 'getTotalBalance',
  });

  // Read allowance
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: TOKEN_ADDRESS,
    abi: baseErc20Abi,
    functionName: 'allowance',
    args: address ? [address, TOKEN_BANK_ADDRESS] : undefined,
    query: { enabled: !!address },
  });

  const { writeContract, data: writeHash, isPending: isWriting } = useWriteContract();

  const { isLoading: isWaiting, isSuccess: txSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  useEffect(() => {
    if (writeHash) {
      setTxHash(writeHash);
    }
  }, [writeHash]);

  useEffect(() => {
    if (txSuccess) {
      refetchTokenBalance();
      refetchDepositBalance();
      refetchAllowance();
      refetchTotalBalance();
      setTxHash(undefined);
      setAmount('');
      setEip7702Processing(false);
      setEip7702Error(null);
    }
  }, [txSuccess, refetchTokenBalance, refetchDepositBalance, refetchAllowance, refetchTotalBalance]);

  // Reset SIWE auth and transfers when wallet account changes
  useEffect(() => {
    setSiweAuthed(false);
    setTransfers([]);
  }, [address]);

  const tokenDecimals = (decimals as number) ?? 18;

  const parsedAmount = (() => {
    try {
      return amount ? parseUnits(amount, tokenDecimals) : BigInt(0);
    } catch {
      return BigInt(0);
    }
  })();

  function handleApprove() {
    if (!parsedAmount) return;
    writeContract({
      address: TOKEN_ADDRESS,
      abi: baseErc20Abi,
      functionName: 'approve',
      args: [TOKEN_BANK_ADDRESS, parsedAmount],
    });
    setAction('approve');
  }

  function handleDeposit() {
    if (!parsedAmount) return;
    writeContract({
      address: TOKEN_BANK_ADDRESS,
      abi: tokenBankAbi,
      functionName: 'deposit',
      args: [parsedAmount],
    });
    setAction('deposit');
  }

  function handleWithdraw() {
    if (!parsedAmount) return;
    writeContract({
      address: TOKEN_BANK_ADDRESS,
      abi: tokenBankAbi,
      functionName: 'withdraw',
      args: [parsedAmount],
    });
    setAction('withdraw');
  }

  const [eip7702Processing, setEip7702Processing] = useState(false);
  const [eip7702Error, setEip7702Error] = useState<string | null>(null);

  async function handleEIP7702Deposit() {
    if (!address || !parsedAmount) return;
    setEip7702Processing(true);
    setEip7702Error(null);

    try {
      const approveCalldata = encodeFunctionData({
        abi: baseErc20Abi,
        functionName: 'approve',
        args: [TOKEN_BANK_ADDRESS, parsedAmount],
      });

      const depositCalldata = encodeFunctionData({
        abi: tokenBankAbi,
        functionName: 'deposit',
        args: [parsedAmount],
      });

      const ethereum = (window as any).ethereum;
      if (!ethereum) {
        throw new Error('未检测到 MetaMask');
      }

      const chainIdHex = await ethereum.request({ method: 'eth_chainId' });

      const result = await ethereum.request({
        method: 'wallet_sendCalls',
        params: [{
          version: '2.0.0',
          chainId: chainIdHex,
          from: address,
          atomicRequired: true,
          calls: [
            { to: TOKEN_ADDRESS, data: approveCalldata, value: '0x0' },
            { to: TOKEN_BANK_ADDRESS, data: depositCalldata, value: '0x0' },
          ],
        }],
      });

      const bundleId = result.id;
      let pollCount = 0;
      const poll = setInterval(async () => {
        try {
          pollCount++;
          const status = await ethereum.request({
            method: 'wallet_getCallsStatus',
            params: [bundleId],
          });
          const code = Number(status.status);
          if (code === 200) {
            clearInterval(poll);
            const txHash = status.receipts?.[0]?.transactionHash;
            if (txHash) setTxHash(txHash as `0x${string}`);
            setAction('eip7702Deposit');
            setEip7702Processing(false);
          } else if (code >= 400 || pollCount > 30) {
            clearInterval(poll);
            setEip7702Error(code >= 400 ? `批量交易失败 (status: ${code})` : '交易确认超时，请检查钱包');
            setEip7702Processing(false);
          }
        } catch {
          if (pollCount > 30) {
            clearInterval(poll);
            setEip7702Processing(false);
          }
        }
      }, 2000);
    } catch (err: any) {
      if (err?.code === 4001) {
        setEip7702Error('用户取消了交易');
      } else {
        setEip7702Error(err?.message || err?.code || 'EIP-7702 存款执行失败');
      }
      setEip7702Processing(false);
    }
  }


  async function handleSIWE() {
    if (!address) return;
    setSiweSigning(true);
    try {
      const message = `TokenBank Sign-In\n\nSign this message to verify you own ${address}.\n\nNonce: ${Date.now()}`;
      await signMessageAsync({ message });
      setSiweAuthed(true);
      fetchTransfers(address);
    } catch {
      // user rejected signing
    } finally {
      setSiweSigning(false);
    }
  }

  async function fetchTransfers(addr: string) {
    setTransfersLoading(true);
    try {
      const res = await fetch(`/api/transfers/${addr}?limit=100`);
      const json = await res.json();
      if (json.success) {
        setTransfers(json.data);
      }
    } catch (err) {
      console.error('Failed to fetch transfers:', err);
    } finally {
      setTransfersLoading(false);
    }
  }

  const isProcessing = isWriting || isWaiting || eip7702Processing;
  const hasAllowance =
    allowance !== undefined &&
    (allowance as bigint) >= parsedAmount &&
    parsedAmount > BigInt(0);

  return (
    <div className="app">
      <header className="header">
        <h1 className="title">TokenBank</h1>
        <div className="wallet-section">
          {isConnected ? (
            <div className="wallet-info">
              <span className="wallet-address">
                {address?.slice(0, 6)}...{address?.slice(-4)}
              </span>
              <span className="eth-balance">
                {ethBalance ? Number(formatUnits(ethBalance.value, ethBalance.decimals)).toFixed(4) : '0'} ETH
              </span>
              {siweAuthed ? (
                <span className="siwe-badge">SIWE</span>
              ) : (
                <button
                  className="btn btn-outline btn-sm"
                  onClick={handleSIWE}
                  disabled={siweSigning}
                >
                  {siweSigning ? '签名中...' : '登录'}
                </button>
              )}
              <button className="btn btn-outline" onClick={() => disconnect()}>
                断开连接
              </button>
            </div>
          ) : (
            <button
              className="btn btn-primary"
              onClick={() => connect({ connector: connectors[0] })}
            >
              连接钱包
            </button>
          )}
        </div>
      </header>

      {isConnected && (
        <main className="main">
          <div className="card-grid">
            {/* Token Info Card */}
            <div className="card">
              <h2 className="card-title">代币信息</h2>
              <div className="info-row">
                <span className="info-label">名称</span>
                <span className="info-value">{tokenName ?? '...'}</span>
              </div>
              <div className="info-row">
                <span className="info-label">符号</span>
                <span className="info-value">{tokenSymbol ?? '...'}</span>
              </div>
              <div className="info-row">
                <span className="info-label">银行总存款</span>
                <span className="info-value">
                  {totalBankBalance !== undefined && tokenSymbol
                    ? `${formatUnits(totalBankBalance as bigint, tokenDecimals)} ${tokenSymbol}`
                    : '...'}
                </span>
              </div>
            </div>

            {/* Balance Card */}
            <div className="card">
              <h2 className="card-title">我的余额</h2>
              <div className="info-row">
                <span className="info-label">钱包余额</span>
                <span className="info-value balance">
                  {tokenBalance !== undefined && tokenSymbol
                    ? `${formatUnits(tokenBalance as bigint, tokenDecimals)} ${tokenSymbol}`
                    : '...'}
                </span>
              </div>
              <div className="info-row">
                <span className="info-label">存款余额</span>
                <span className="info-value balance highlight">
                  {depositBalance !== undefined && tokenSymbol
                    ? `${formatUnits(depositBalance as bigint, tokenDecimals)} ${tokenSymbol}`
                    : '...'}
                </span>
              </div>
              <div className="info-row">
                <span className="info-label">授权额度</span>
                <span className="info-value allowance">
                  {allowance !== undefined && tokenSymbol
                    ? `${formatUnits(allowance as bigint, tokenDecimals)} ${tokenSymbol}`
                    : '...'}
                </span>
              </div>
            </div>
          </div>

          {/* Actions Card */}
          <div className="card action-card">
            <h2 className="card-title">操作</h2>
            <div className="input-group">
              <input
                type="text"
                className="amount-input"
                placeholder="输入金额"
                value={amount}
                onChange={(e) => {
                  const v = e.target.value;
                  if (v === '' || /^\d*\.?\d*$/.test(v)) {
                    setAmount(v);
                  }
                }}
                disabled={isProcessing}
              />
              <span className="input-suffix">{tokenSymbol ?? '...'}</span>
            </div>

            {txHash && (
              <div className="tx-notice">
                <span className="spinner" />
                交易处理中...{' '}
                <code className="tx-hash">{txHash.slice(0, 10)}...</code>
              </div>
            )}

            {txSuccess && <div className="tx-notice success">交易成功!</div>}

            <div className="btn-group">
              <button
                className="btn btn-primary"
                onClick={handleApprove}
                disabled={!parsedAmount || isProcessing}
              >
                {isProcessing && action === 'approve' ? '授权中...' : '1. 授权'}
              </button>
              <button
                className="btn btn-success"
                onClick={handleDeposit}
                disabled={!hasAllowance || isProcessing}
              >
                {isProcessing && action === 'deposit' ? '存款中...' : '2. 存款'}
              </button>
              <button
                className="btn btn-danger"
                onClick={handleWithdraw}
                disabled={
                  !parsedAmount ||
                  isProcessing ||
                  !depositBalance ||
                  (depositBalance as bigint) < parsedAmount
                }
              >
                {isProcessing && action === 'withdraw' ? '取款中...' : '3. 取款'}
              </button>
            </div>

            <div className="smart-section">
              <div className="smart-divider">
                <span>EIP-7702 批量存款（授权+存款一体）</span>
              </div>
              <button
                className="btn btn-eip7702"
                onClick={handleEIP7702Deposit}
                disabled={!parsedAmount || !address || isProcessing}
              >
                {eip7702Processing
                  ? '授权签名中...'
                  : isWaiting && action === 'eip7702Deposit'
                  ? '交易确认中...'
                  : '一键授权+存款'}
              </button>
              {eip7702Error && (
                <div className="tx-notice error">{eip7702Error}</div>
              )}
              <p className="hint">
                MetaMask 在 Sepolia 上自动使用 <b>EIP-7702 type-4 授权交易</b>，
                将 approve + deposit 封装为一次原子交易。一次签名，两步完成。
              </p>
            </div>

            <p className="hint">
              常规操作流程：先授权 TokenBank 使用你的代币，再进行存款或取款
            </p>
          </div>

          {/* Transfer Records */}
          {siweAuthed && (
            <div className="card transfer-card">
              <div className="transfer-header">
                <h2 className="card-title">转账记录</h2>
                <button
                  className="btn btn-outline btn-sm"
                  onClick={() => address && fetchTransfers(address)}
                  disabled={transfersLoading}
                >
                  {transfersLoading ? '刷新中...' : '刷新'}
                </button>
              </div>
              {transfers.length === 0 && !transfersLoading ? (
                <p className="transfer-empty">暂无转账记录</p>
              ) : (
                <div className="transfer-table-wrapper">
                  <table className="transfer-table">
                    <thead>
                      <tr>
                        <th>交易哈希</th>
                        <th>区块</th>
                        <th>发送方</th>
                        <th>接收方</th>
                        <th>金额</th>
                      </tr>
                    </thead>
                    <tbody>
                      {transfers.map((t) => (
                        <tr key={t.id}>
                          <td className="mono">
                            {t.tx_hash.slice(0, 10)}...
                          </td>
                          <td>{t.block_number}</td>
                          <td className="mono">
                            {t.from_address.toLowerCase() === address?.toLowerCase() ? (
                              <span className="tag tag-self">自己</span>
                            ) : (
                              `${t.from_address.slice(0, 6)}...${t.from_address.slice(-4)}`
                            )}
                          </td>
                          <td className="mono">
                            {t.to_address.toLowerCase() === address?.toLowerCase() ? (
                              <span className="tag tag-self">自己</span>
                            ) : (
                              `${t.to_address.slice(0, 6)}...${t.to_address.slice(-4)}`
                            )}
                          </td>
                          <td className={`transfer-amount ${t.from_address.toLowerCase() === address?.toLowerCase() ? 'in' : 'out'}`}>
                            {t.from_address.toLowerCase() === address?.toLowerCase() ? '+' : '-'}
                            {formatUnits(BigInt(t.amount), tokenDecimals)} {tokenSymbol ?? ''}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}
        </main>
      )}

      {!isConnected && (
        <div className="connect-prompt">
          <div className="prompt-card">
            <h2>欢迎使用 TokenBank</h2>
            <p>请连接钱包以开始使用存款和取款功能</p>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
