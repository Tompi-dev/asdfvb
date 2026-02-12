// Конфигурация контракта
const CONTRACT_ADDRESS = '0x2664e4559370ce58F4FEd8A1e9F1e37FE587f98A'; // Заменить после деплоя
const CONTRACT_ABI = [
  {
    "inputs": [
      { "internalType": "string", "name": "_title", "type": "string" },
      { "internalType": "string", "name": "_description", "type": "string" },
      { "internalType": "uint256", "name": "_goalAmount", "type": "uint256" },
      { "internalType": "uint256", "name": "_durationDays", "type": "uint256" }
    ],
    "name": "createCampaign",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{ "internalType": "uint256", "name": "_campaignId", "type": "uint256" }],
    "name": "contribute",
    "outputs": [],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [{ "internalType": "uint256", "name": "_campaignId", "type": "uint256" }],
    "name": "finalizeCampaign",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{ "internalType": "uint256", "name": "_campaignId", "type": "uint256" }],
    "name": "getCampaignDetails",
    "outputs": [
      { "internalType": "address", "name": "", "type": "address" },
      { "internalType": "string", "name": "", "type": "string" },
      { "internalType": "string", "name": "", "type": "string" },
      { "internalType": "uint256", "name": "", "type": "uint256" },
      { "internalType": "uint256", "name": "", "type": "uint256" },
      { "internalType": "uint256", "name": "", "type": "uint256" },
      { "internalType": "bool", "name": "", "type": "bool" }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{ "internalType": "address", "name": "account", "type": "address" }],
    "name": "balanceOf",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "campaignCount",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  }

];


let web3;
let contract;
 async function loadCampaigns() {
  const count = Number(await contract.methods.campaignCount().call());
  const list = [];

  for (let i = 1; i <= count; i++) {
    const d = await contract.methods.getCampaignDetails(i).call();

    list.push({
      id: d.id ?? d[0],
      creator: d.creator ?? d[1],
      title: d.title ?? d[2],
      description: d.description ?? d[3],
      goalAmount: d.goalAmount ?? d[4],
      deadline: d.deadline ?? d[5],
      amountRaised: d.amountRaised ?? d[6],
      finalized: d.finalized ?? d[7],
    });
  }

  console.log("campaigns:", list);
}

let isActive = true;

// Инициализация приложения
window.addEventListener('load', async () => {
    if (typeof window.ethereum !== 'undefined') {
        console.log('MetaMask detected!');
        web3 = new Web3(window.ethereum);
    } else {
        showAlert('Please install MetaMask!', 'error');
    }
    
    document.getElementById('connectWallet').addEventListener('click', connectWallet);
    document.getElementById('createCampaignForm').addEventListener('submit', createCampaign);
});

// Подключение к MetaMask
async function connectWallet() {
    try {
        const accounts = await ethereum.request({ method: 'eth_requestAccounts' });
        userAccount = accounts[0];
        
        // Проверка сети
        const chainId = await ethereum.request({ method: 'eth_chainId' });
        const networkName = getNetworkName(chainId);
        
        if (!isTestNetwork(chainId)) {
            showAlert('Please switch to a test network (Sepolia, Holesky, or Localhost)', 'error');
            return;
        }
        
        // Инициализация контракта
        contract = new web3.eth.Contract(CONTRACT_ABI, CONTRACT_ADDRESS);
        
        // Обновление UI
        //async function refundCampaign(id) {
            // try {
            //     const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
            //     const user = accounts[0];

            //     await contract.methods.refund(id).send({ from: user });

            //     alert("Refund successful!");
            //     loadCampaigns();
            //     updateBalances();
            // } catch (error) {
            //     console.error(error);
            //     alert("Refund failed: " + error.message);
            // }
            // }




        document.getElementById('address').textContent = formatAddress(userAccount);
        document.getElementById('networkBadge').textContent = networkName;
        document.getElementById('walletAddress').style.display = 'block';
        document.getElementById('connectWallet').textContent = 'Connected';
        
        // Загрузка данных
        await loadUserData();
        await loadCampaigns();
        
        showAlert('Wallet connected successfully!', 'success');
        
        // Слушаем события смены аккаунта
        ethereum.on('accountsChanged', handleAccountsChanged);
        ethereum.on('chainChanged', () => window.location.reload());
        
    } catch (error) {
        console.error('Connection error:', error);
        showAlert('Failed to connect wallet: ' + error.message, 'error');
    }
}

// Загрузка данных пользователя
async function loadUserData() {
    try {
        // Баланс ETH
        const ethBalance = await web3.eth.getBalance(userAccount);
        document.getElementById('ethBalance').textContent = 
            parseFloat(web3.utils.fromWei(ethBalance, 'ether')).toFixed(4);
        
        // Баланс NOVA токенов
        const novaBalance = await contract.methods.balanceOf(userAccount).call();
        document.getElementById('novaBalance').textContent = 
            parseFloat(web3.utils.fromWei(novaBalance, 'ether')).toFixed(0);
        
    } catch (error) {
        console.error('Error loading user data:', error);
    }
}

// Загрузка кампаний
async function loadCampaigns() {
    try {
        const campaignCount = await contract.methods.campaignCount().call();
        document.getElementById('totalCampaigns').textContent = campaignCount;
        
        const campaignsList = document.getElementById('campaignsList');
        campaignsList.innerHTML = '';
        
        let totalRaised = 0;
        
        for (let i = 0; i < campaignCount; i++) {
            const details = await contract.methods.getCampaignDetails(i).call();
            const [creator, title, description, goal, deadline, raised, finalized] = details;
            
            totalRaised += parseFloat(web3.utils.fromWei(raised, 'ether'));
            
            const progress = (
              parseFloat(web3.utils.fromWei(raised, 'ether')) /
              parseFloat(web3.utils.fromWei(goal, 'ether'))
            ) * 100;
            const daysLeft = Math.max(0, Math.floor((deadline - Date.now() / 1000) / 86400));
            
            const card = document.createElement('div');
            card.className = 'campaign-card';
            card.innerHTML = `
                <div class="campaign-title">${title}</div>
                <p style="opacity: 0.8; margin: 10px 0;">${description}</p>
                <div style="margin: 15px 0;">
                    <strong>Goal:</strong> ${web3.utils.fromWei(goal, 'ether')} ETH<br>
                    <strong>Raised:</strong> ${web3.utils.fromWei(raised, 'ether')} ETH<br>
                    <strong>Days left:</strong> ${daysLeft} days
                </div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: ${Math.min(progress, 100)}%"></div>
                </div>
                <div style="margin-top: 15px;">
                    <input type="number" id="amount-${i}" placeholder="0.01" step="0.01" 
                           style="width: calc(100% - 110px); margin-right: 10px;">
                    <button class="btn" onclick="contributeTocampaign(${i})" 
                            ${finalized ? 'enabled' : ''}>
                        ${finalized ? 'Ended' : 'Support'}
                    </button>
                </div>
            `;
            campaignsList.appendChild(card);
        }

       
   
       
        document.getElementById('totalRaised').textContent = totalRaised.toFixed(2);
        
    } catch (error) {
        console.error('Error loading campaigns:', error);
    }
}

// Создание кампании
async function createCampaign(e) {
    e.preventDefault();
    
    if (!userAccount) {
        showAlert('Please connect your wallet first', 'error');
        return;
    }
    
    const title = document.getElementById('campaignTitle').value;
    const description = document.getElementById('campaignDescription').value;
    const goal = document.getElementById('goalAmount').value;
    const duration = document.getElementById('duration').value;
    
    try {
        const goalWei = web3.utils.toWei(goal, 'ether');
        
        showAlert('Creating campaign... Please confirm transaction', 'success');
        
        const result = await contract.methods
            .createCampaign(title, description, goalWei, duration)
            .send({ from: userAccount });
        
        showAlert('Campaign created successfully! 🎉', 'success');
        
        // Очистка формы
        document.getElementById('createCampaignForm').reset();
        
        // Перезагрузка кампаний
        await loadCampaigns();
        
    } catch (error) {
        console.error('Error creating campaign:', error);
        showAlert('Failed to create campaign: ' + error.message, 'error');
    }
}

// Внесение вклада
async function contributeTocampaign(campaignId) {
    const amount = document.getElementById(`amount-${campaignId}`).value;
    
    if (!amount || parseFloat(amount) <= 0) {
        showAlert('Please enter a valid amount', 'error');
        return;
    }
    
    try {
        const amountWei = web3.utils.toWei(amount, 'ether');
        
        showAlert('Processing contribution... Please confirm transaction', 'success');
        
        const result = await contract.methods
            .contribute(campaignId)
            .send({ 
                from: userAccount,
                value: amountWei 
            });
        
        showAlert(`Contribution successful! You earned NOVA tokens! 🎁`, 'success');
        
        // Обновление данных
        await loadUserData();
        await loadCampaigns();
        
    } catch (error) {
        console.error('Error contributing:', error);
        showAlert('Failed to contribute: ' + error.message, 'error');
    }
}

// Вспомогательные функции
function formatAddress(address) {
    return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
}

function getNetworkName(chainId) {
    const networks = {
        '0x1': 'Mainnet',
        '0xaa36a7': 'Sepolia',
        '0x4268': 'Holesky',
        '0x539': 'Localhost'
    };
    return networks[chainId] || 'Unknown';
}

function isTestNetwork(chainId) {
    const testNetworks = ['0xaa36a7', '0x4268', '0x539'];
    return testNetworks.includes(chainId);
}

function showAlert(message, type) {
    const alertsDiv = document.getElementById('alerts');
    const alert = document.createElement('div');
    alert.className = `alert alert-${type}`;
    alert.textContent = message;
    alert.style.display = 'block';
    
    alertsDiv.innerHTML = '';
    alertsDiv.appendChild(alert);
    
    setTimeout(() => {
        alert.style.display = 'none';
    }, 5000);
}

function handleAccountsChanged(accounts) {
    if (accounts.length === 0) {
        showAlert('Please connect to MetaMask', 'error');
    } else {
        userAccount = accounts[0];
        window.location.reload();
    }
}