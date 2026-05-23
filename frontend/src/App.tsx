import { useState, useEffect } from 'react';
import {
  useAccount,
  useConnect,
  useDisconnect,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
  useBalance,
} from 'wagmi';
import { formatUnits, parseUnits } from 'viem';
import { baseErc20Abi } from './contracts/BaseERC20';
import { tokenBankAbi } from './contracts/TokenBank';
import { TOKEN_ADDRESS, TOKEN_BANK_ADDRESS } from './contracts/addresses';
import './App.scss';

function App() {
  const { address, isConnected } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();
  const { data: ethBalance } = useBalance({ address });

  const [amount, setAmount] = useState('');
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const [action, setAction] = useState<'approve' | 'deposit' | 'withdraw'>('deposit');

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
  const { data: totalBankBalance } = useReadContract({
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
      setTxHash(undefined);
      setAmount('');
    }
  }, [txSuccess, refetchTokenBalance, refetchDepositBalance, refetchAllowance]);

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

  const isProcessing = isWriting || isWaiting;
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

            <p className="hint">
              操作流程：先授权 TokenBank 使用你的代币，再进行存款或取款
            </p>
          </div>
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
