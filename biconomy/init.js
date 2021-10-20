const magic = new Magic("pk_test_93B08330447C2AAB", { network: "kovan" });
const biconomy = new Biconomy(
  new ethers.providers.Web3Provider(magic.rpcProvider),
  {
    apiKey: "CTGkNtqm8.bce042dc-0ed2-4845-869a-4d178f2465b0",
    debug: true,
  }
);
const provider = new ethers.providers.Web3Provider(biconomy);
const signer = provider.getSigner();

const handleLogin = async (email) => {
  // Authenticate user
  await magic.auth.loginWithMagicLink({ email });
  console.log("User is logged in.");
  $("#section-login").hide();
};

$("#btn-login").click(async () => {
  const email = $("#email").val();
  await handleLogin(email);
});

$("#btn-transact").click(async () => {
  const userAddr = await signer.getAddress();
  console.log(`transacting with ${userAddr}`);

  // forwarder contract is "0xF82986F574803dfFd9609BE8b9c7B92f63a1410E"
  const contractAddr = "0x9669E5dFa7C3Ae54a4d5506Ec735931D8E6707d0";

  // Initialize Constants
  const contract = new ethers.Contract(
    contractAddr,
    '[{"inputs":[{"internalType":"address","name":"_trustedForwarder","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"inputs":[],"name":"decrement","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"increment","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"forwarder","type":"address"}],"name":"isTrustedForwarder","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_trustedForwarder","type":"address"}],"name":"setTrustedForwarder","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"trustedForwarder","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"versionRecipient","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"}]',
    signer
  );

  // Get data for the transaction we want to call
  const { data } = await contract.populateTransaction.increment();
  //   const provider = biconomy.getEthersProvider();

  console.log({ data });
  const txParams = {
    data,
    to: contractAddr,
    from: userAddr,
    signatureType: "EIP712_SIGN",
  };

  // Biconomy team note: as ethers does not allow providing custom options while sending transaction
  // cto of biconomy: https://github.com/ethers-io/ethers.js/discussions/1313#discussioncomment-399944
  //  See https://ethereumbuilders.gitbooks.io/guide/content/en/ethereum_json_rpc.html#eth_sendtransaction
  // Signature type is not an expectfield in the object passed into the array
  // Biconomy reads this field and passes on your transaction
  console.log({ biconomy });
  const tx = await provider.send("eth_sendTransaction", [txParams]);
  console.log(`Transaction hash ${tx}`);

  // event emitter methods
  provider.once(tx, (transaction) => {
    // Emitted when the transaction has been mined
    //show success message
    console.log(transaction);
    //do something with transaction hash
  });
});

const foo = async () => {
  console.log("running foo");
  return signer.getAddress();
};
foo()
  .then((res) => console.log({ res }))
  .catch((err) => console.log({ err }));
