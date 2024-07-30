// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "src/test/TestPlus.sol";

import {UltraLRT, Math} from "src/vaults/restaking/UltraLRT.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {EigenDelegator} from "src/vaults/restaking/EigenDelegator.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {EigenDelegator, WithdrawalInfo, IStrategy} from "src/vaults/restaking/EigenDelegator.sol";
import {DelegatorFactory} from "src/vaults/restaking/DelegatorFactory.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/console2.sol";

import {
    WithdrawalInfo,
    QueuedWithdrawalParams,
    ApproverSignatureAndExpiryParams,
    IDelegationManager,
    IStrategyManager,
    IStrategy
} from "src/interfaces/eigenlayer/eigen.sol";

contract UltraLRTV2 is UltraLRT {
    // will have the same decimals as asset
    function _initialShareDecimals() internal pure override returns (uint8) {
        return 0;
    }
}

contract UltraLRT_Int_Test is TestPlus {
    UltraLRT eigenVault = UltraLRT(0x47657094e3AF11c47d5eF4D3598A1536B394EEc4);
    UltraLRT symVault = UltraLRT(0x0D53bc2BA508dFdf47084d511F13Bb2eb3f8317B);

    UltraLRT newEigenVault;
    UltraLRT newSymVault;

    function _deployNewEigenVault() internal {
        address operator = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5; // p2p

        ERC20 asset = ERC20(eigenVault.asset());
        // ultra LRT impl
        UltraLRTV2 impl = new UltraLRTV2();
        // delegator implementation
        EigenDelegator delegatorImpl = new EigenDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), governance);
        // initialization data
        bytes memory initData =
            abi.encodeCall(UltraLRT.initialize, (governance, address(asset), address(beacon), "uLRT", "uLRT"));
        // proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        // upgradeable vault
        UltraLRTV2 vault = UltraLRTV2(address(proxy));

        // set delegator factory
        DelegatorFactory dFactory = new DelegatorFactory(address(vault));

        vm.prank(governance);
        vault.setDelegatorFactory(address(dFactory));

        // add withdrawal escrow
        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);
        vm.prank(governance);
        vault.setWithdrawalEscrow(escrow);

        // create 1 delegator
        vm.prank(governance);
        vault.createDelegator(operator);

        vm.prank(governance);
        vault.setMaxUnresolvedEpochs(10);
        newEigenVault = UltraLRT(address(vault));

        // set old vault as harvester role
        bytes32 role = vault.HARVESTER();
        vm.prank(governance);
        vault.grantRole(role, address(eigenVault));
    }

    function _deployNewSymVault() internal {
        address operator = 0xC329400492c6ff2438472D4651Ad17389fCb843a; // p2p

        ERC20 asset = ERC20(symVault.asset());
        // ultra LRT impl
        UltraLRTV2 impl = new UltraLRTV2();
        // delegator implementation
        SymbioticDelegator delegatorImpl = new SymbioticDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), governance);
        // initialization data
        bytes memory initData =
            abi.encodeCall(UltraLRT.initialize, (governance, address(asset), address(beacon), "uLRTs", "uLRTs"));
        // proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        // upgradeable vault
        UltraLRTV2 vault = UltraLRTV2(address(proxy));

        // set delegator factory
        DelegatorFactory dFactory = new DelegatorFactory(address(vault));

        vm.prank(governance);
        vault.setDelegatorFactory(address(dFactory));

        // create delegator
        vm.prank(governance);
        vault.createDelegator(operator);

        // add withdrawal escrow
        WithdrawalEscrowV2 escrow = new WithdrawalEscrowV2(vault);
        vm.prank(governance);
        vault.setWithdrawalEscrow(escrow);

        newSymVault = UltraLRT(address(vault));

        // set old vault as harvester role
        bytes32 role = vault.HARVESTER();
        vm.prank(governance);
        vault.grantRole(role, address(symVault));
    }

    function setUp() public {
        vm.createSelectFork("ethereum", 20_421_491);
        governance = eigenVault.governance();
        _deployNewEigenVault();
        _deployNewSymVault();
    }

    function testSymMigration() public {
        address[339] memory users = [
            0x90153be2aC32633fC9A7Cc53cdF01D348E875555,
            0x23E0E9D8B87920440204369B35c566017F2bAeC9,
            0x1688325FEf3B02143bA44880a43DccE339f004c0,
            0x05A13DCf55Ea6D532f15284F39e02811FC183a8a,
            0xB2185c92a4eAF0Dd1BF6a5476363444dE9831EAC,
            0x40F832B71D2C525A9aa4b4908Ec511Ed93c8a308,
            0x9482C72Cb018eE03d8c23395038B510ED4e6040C,
            0x7BFEe91193d9Df2Ac0bFe90191D40F23c773C060,
            0x8b2d590b8ddABd93cf81Ac702653E54Fb0dfC9A7,
            0xEb4Db23c27253077Fb3080adda6C5C127b0dACAe,
            0x804212E2D255642ED2376e4DF0133bC20B9c487d,
            0x418A983FDff31d5b4A2196D14604a01EB52dC5f6,
            0x660A52712Bc9b1cc41149747b220bb73D6C24a4e,
            0xe5048Cd6ed8aE117ceB935A24211882d0AA1879A,
            0x389b404614e53248f542B1daafad38aF9ff686e5,
            0x5d47e5D242a8F66a6286b0a2353868875F5d6068,
            0x6d4F97bC946e75b3E7ECDd88deDaCbe46Cd41870,
            0xB0FEcff8Ab2b45778Cc022f7f0f98D0A2B0133a0,
            0xE63eB4131fE0D39f8B21C058fb5F029B8B8f5Ab9,
            0x3F62E4C7C23f540445534a9ce62E7b9BE45333AF,
            0x537875EF902E5C9749a8Ba4C9Ebf34D9734da1Dc,
            0xA3722b0dF43E0349517CBE969AdfafEF49Aa05Dc,
            0x4BCc30fbafCD97b31c926266129e30942cD2303E,
            0x379CAdAb8F98bF10121E2e9B7fc02CA802345E8b,
            0xC23598944699d9768A41506CC955d79DBc6778e5,
            0xF93A5F0A4925EeC32cD585641c88a498523f383C,
            0xcd92B68b5513936870b12a9ad3F6b15254C2d6D5,
            0x76337B85c89Bb576BF9Ca773Ebf40A2b057d39fd,
            0x470D235cA1CafF614AbEE02D98Ac3aa89A6758bD,
            0x0bA9de69Ab5A21B63d4BD2D6634110c1564a62A3,
            0xB4B6789D731A63b3C2B3e435b4Aef6CB6B9e375c,
            0x27BF1A914B09F89c629AcEFA371B598a5857CcB0,
            0xc6404f24DB2f573F07F3A60758765caad198c0c3,
            0x569E0d84FBc09006049057CC6F9538103635fFf8,
            0x39B23Dec93995a60f21D771aeC3A5A1Fbf2E646B,
            0xb6b7bBC6F44f5F09eeBAfcEACB34420f5319b8Bf,
            0x9616A71063d890374718d3Df3652391703ab7F84,
            0xF3D7459C7F6F75252AAdF594D2Ea74F04B359F82,
            0x054BA727e6141d0761e8E0C3F300bF8DD8A4A11F,
            0x87a6b68204D5e6EdEe3a9D191f09D201852B0eA3,
            0xf6237610007fCa2B99fb776AbdeAbD80ad2fd252,
            0x70800ff6c6a9b6Ef823B12F85FE0CF0CD00bB60b,
            0xf3fc15A1A6Ee6d7a5879e53c22787c1C7165A685,
            0x0CCfA1c3441F3fEbDcEE067bd1Cbe3af7BBB614b,
            0x860457234bBFE0ba38Da57C67e17f07b22ED501e,
            0xEBcC98573c3cd9b5B61900D1304DA938B5036a0d,
            0xCa1f1977ACbff4Afc4D77fd32cf1D412Ae2C12bF,
            0x5221FE845a6eb381AF787196D70cDA5Cda6DECE4,
            0x8b5ff6736CbfBa804F97C5f27a1DAD35C520e4f6,
            0xF87F2c4EcD0EBd316A6965362d0260E70893c8D6,
            0x10eB74E3BF7aa53C4ce96468A318e5813DCB9A9B,
            0x30ee1f53c0e9489fDeB7047d005684D641bAfb37,
            0x44e5e98b06055B67b787E16fDc17Cc55073aCf49,
            0x1405704e578296aFFeCb196862d0Db4f07A3d097,
            0x9c813c2fe8aDcA8bCd45a0799af01e5ddE075bd0,
            0x5535C48511FaA34bC3666f385b9B3aB93a65f845,
            0x841AD0AbAb2D33520ca236A2F5D8b038adDc12BA,
            0x6783f6DD9dc6C4e01f1F180ca5633D99565f71E5,
            0xAea07781fd5Fd57f363DDB161b47Fc34627C95BE,
            0xa97E9BA560042d1141b344DBDBC5915aD9FBb88e,
            0xd253CCA4B130Cc7f7C90312E2A13B1dB3441f76a,
            0x4226267d8f1C0C57aa3404605c900a03c91a084E,
            0x92509e216963F165595dF768c081b2d8B1cE0E1f,
            0xAdade4421AA9877fe2628F246BC025EdceD81790,
            0x1793699B4924E3a7330afeDd54B00B79B70601DE,
            0xeB42dDFff586580Df11a99Bcdfb12B9765fE864c,
            0xCAE3c3A245F9C1C73F4CAf05F8157d48703801F5,
            0x607aAFcca9d4F0179C7685c3C65c7a084275Dd8c,
            0x0Dd64BCAD684b951189A474Dc5d48BF37193B9BC,
            0x0C5B80a28D1d825De781dD9562Ea3582A5280544,
            0xAeAA59F7FF11c931AcDdcd73f7C0BBf3120370D1,
            0x98F3d011e0BFBF7d6a118bd300914D78D0Efb36A,
            0x23572b691aE68f4E0473d78122A408F47261b94D,
            0xdac06Aa8ecd8c9A0F814FFDA10B92971612DF314,
            0x6953358517E9a5cc92274D1DD746A470654D37C2,
            0xA6bb6531Ff5027f316b2516bc87c6478559476a7,
            0x8007221Ab6BdB20496eb74D038CbC5D590D1BEa9,
            0xDDB2e39f202f5f119Bf1ec2eD1012a2f5a046c92,
            0xdC09EdF802121fbbECc6C974a3F9ee02025A1C66,
            0x43b8D78925c96061C5905f3f2f713E9823dC34E6,
            0xADfbEDB4c296aF49Ca39c518daA261Fe0E336DED,
            0x73fA019C419CcEa5Cd1b7F79C8d161954B73FCdf,
            0xE440f96287F734C573d78b806f1d6B47584E20A8,
            0xA455EdF4e26e6090F926BB81ef5C773538D96eF4,
            0xf42747ad461e6ea493Ff7EfF17baE4E34c06477c,
            0xbe093648274161760D62A6b7238434eAee37A68C,
            0xFA97E0E34D6324b871fAC14D447aE0C8b837dFc9,
            0xEE2951198ad5D07329B23b896ef51009032Fc38a,
            0x7AFD3c9b8AFA8d69159fE78719111A039Dfc9a54,
            0x6d0F4d31A91DC604B7264B718822607A254e5052,
            0x06bF0460DA579c52DE0356423dfe9979b54C84d3,
            0xeeF9F12cDFe9E79709dbf6879D0C12C0b367013B,
            0xBa23Cd29a0D0A50716e613AC4eEa49c04c10d6D8,
            0xd1543Ae2cc815b510d64a404EC58B3d4179cB2B5,
            0x484562740c97E67382A3a2eF9423474752936339,
            0x3DEFDAa12778d36892800Ff2F59827997066137d,
            0xF9789816776474eF323c82bA583521472f8A674f,
            0x014068eaE1202A7e254DdA56B8C7Df36B54Bc33C,
            0xbb46131D139b64B5739c857c1583C07cA34e7B2F,
            0x919c5e27a93222Dd99078F5192b41423B6e6447f,
            0x5923659ddE20a78eE18Ae4ce539654cB6d32cd97,
            0xcB0d8e4AB1549d6f10Fba323FB73a1F4487cd986,
            0x62beE234b4066af4709DeE5FD3FFCed6782f5C0D,
            0x9Ed713f08a834116109803e9b13fB16f2D965bDd,
            0xD5891c4c48782839C433b4e1D6Dc8d825cD12565,
            0x24752bC19ee968BFDE3c828f7adeea794Bd040FA,
            0xdd0206010CA82fF22303b58863b3a6f3006C86C4,
            0xF40E60F44163BDF8De5B7227f0F41a35bA09790b,
            0xEfbC53e0AFdc9f649Bc1Ab692461df57E70A560f,
            0x384D7a6ab19394e4587d467D713b1276d2bA4Be3,
            0xD8623C5b259B0b15555002C6718e257c06685cD4,
            0x68977a1f7Ea1724974E27B97Cb2545074f9004dE,
            0xdCCe85DFe9beA17Dfcf9f98f6B7a25A0CFEfeAed,
            0xdD3376a23A8DEf45a7e0A9a9E8631ABF875616Ab,
            0x38bbac4D53CDcB73e0fbB4f068731Ec5A3d75BdB,
            0x949a35296DA83c44c1cc49ad29A476E1652d49ec,
            0xb4F4642997Ab9952761ff2f00D12B251285fA867,
            0xf9D7db70fbf15b1f9D7cF73b927E02A51ae491DF,
            0x80C9f5Cf673D93F606bb7A0EcF8A38BE255E9684,
            0x696dC914cDbe138Db2325b9BE840F56750AA1b90,
            0xf38E04D7663b6162f9A1FC923AB5fAff45c11a34,
            0x802BC4012B32e7c6bFc65c446A3E04e7BBFBDAd0,
            0x1DE83E6c96fB3e109EfC0E781D43B315f947adF9,
            0x7363c82AF29aD0b64283BB0Ce307D16054d094D6,
            0xf20d9E25BF9767629f66342fDff519AD07a1C3B5,
            0x25FA68A4c340202737EDBC67fD1a2Ec8DE872dB6,
            0xE7d8Be1784eCdF2dAf891180AeD19b3AFA5130bd,
            0x1FcFf5E7a50BA2391b27995C4Ee0f123B8a99ac5,
            0x0aAF37c3EaaA42d417434Fd2ceC555846D46415C,
            0x23286E812D1936a86C85c33c0523E048bA6AD1B0,
            0x8fa74d850BabB2b21ba2Ea1f8c9CcD13770864cD,
            0xf4bA8e97d59284ebfc7ab33a509bb8938748d492,
            0x8cFdD06610fc54460170796c32aAc88bF5BFb40D,
            0xB5a03c23869d658Bf3aEA5e4E07B7f89110f6a2C,
            0x76081116F51736a21E47Ada6182a0809ee6C1688,
            0x9C85C376A50721c75E4E015AC22EfE066dbB73EC,
            0x46F0F7FE85C7924e4122dD5Cf035dB9a06881B7e,
            0x6Bf5192C6BD11d16EA73aAF2f2E4F585899BDBd9,
            0x19272849D235D523D4ACFD1bfa27E4e2C6e1B682,
            0x14d977f58D51430982B2ba49b8c70F365c777024,
            0x5c703F5131bB3268E0dC32913a3c0994eda215Fe,
            0x70B63Ce380f79082A4ccf355e0a49db44aD48f90,
            0x85763159E8fD3171eaE774Bba5dBbEea96303F09,
            0x7d262860b82a98b5eC549714bFc1D4a7F568d722,
            0x2A5A6cF15d284d818EeFEb6282756178F271ed6d,
            0x67aFd790133EA65C16A1Ac0734345C5151a2a042,
            0x8C97a4B06E12f87519c2C216C35711651112b824,
            0xB4a76d08a6645c02640440b34f58e2940a0736f6,
            0xc3b84470e7D1Dc53252a577AFA28b3dfbB6216bA,
            0xbfec58BfA18c8636C403cb7BFABcf264a5E5Fcc3,
            0x959c85Be0261b59FDe1816336AC6f7fB8EF985c2,
            0xD381BeD5540aa911181d57cECec4fdfc3fF3428f,
            0x5878A46F806CF120AE5c11b4609bBB1cC093C701,
            0xb581d4DE6394980A82C02D6f7B1765E92a1C6608,
            0xE7029eD46B9BB956d654E20231DF69eCA2dFF621,
            0x5260285f859a4460905c567562600026124bE39b,
            0x29a7dAD8F99fA3C7BC39D232415908bfd5528FcF,
            0x56a7473262928DDe9eCdC9A7aa74028228d34896,
            0xE3D61d88D3A05455F664542e3B3685E0F7bd7CD9,
            0xa83Ceda1edC2E75999D89e62d0BFa383f27f2ddE,
            0xfE5d5B8A18aF8f877DFb5037Ca84D37221540F1C,
            0x047fF53731AadEF85e0c518CA34977f48311a689,
            0xfA3E7201559C1aE9C0527bA0baba991151A9F790,
            0x20FbA32aEccd8B98A3E3072dd3bCD6A7D81d8DB0,
            0x524Bc4F914F91923B1507ea8E4C6cA4d5Ec80dc1,
            0xdc460982Caa040470b8EB635aE29f26BcCA44ee1,
            0xBF460849BEB853F0b46f6D46fa2eD76eF1E23bE2,
            0x4E535Cbf48f24a420Ba1c7852c9137785d8C314D,
            0x5E09dba055f417eE82461bA858e0C7AF7DA760fc,
            0x802f7A83325e6d6b11fAD88C66c4040DBC2bE93d,
            0x5CD4c786de7Dd4DF2a3a924AC535f48dE9eF3550,
            0x8955c241e091f68c0D0f2FAE31A2796181ef6a9b,
            0x25122ecd3e80E8884bD2A1e56c347542c7AD5250,
            0x117E1DC8c0E23dcDBa18D4F662449dc692c9215a,
            0xC29Cfde65AbeEf6fD2B4f65E2637e975E4186F89,
            0xf5Fa0f11364Cc7695c2E8c3F7C9a7dE3EA2483f1,
            0xab07f7c93713D0864E7547C66D706B687B6300AF,
            0x036378Fcff3D5CC29198dd09139b9Bc9DA8eA84f,
            0xD1736cAC8c3497bA0C68Fd515479C3f4fCc891B1,
            0xd561FaA6D9895F52EA8d23f24b3299E12382C49B,
            0xD375DdfC27C6422500123FBC4CA0141aFDc17244,
            0x3A752abca8d4b3D9DB14339Eb1AeDD7Aa083700D,
            0x706f9AC0C9d08d725B899cC8C2582620745CF930,
            0x33abAf6F3D324c68140932903FCf108cfb0548B0,
            0x1dF2535cf0956AbEC21C4738534885d3849d6578,
            0xe1c52e91A4D221be28C2e5e0aeD0dA51b5cD504e,
            0xD5f58F8c3a22DcB55cA66583b8234D489983ACC8,
            0xb36F9f412959F40ca65599BFd6Ac67d5b883d1D6,
            0x0f835F53169F13Ff09Fd5C5b0709cB115Ed223bE,
            0x714Cb1145218871fAebD55de36dBE7053cc9C74d,
            0x012B0Ee819efD549F91B110c4A067e8165221b1f,
            0x417Bc6720A8e45AA67EDa4006A86460B285a3Fa5,
            0x2b4098a2839651b238198A9F759975DD5027fa25,
            0x83c0E2F92cAbA9D0FD63b5A695AFf73eF67fdAd7,
            0x8c1213A88aD026cda38E3b11ECC159e3F53871fa,
            0x01004bEa6919b67C1475756EA75019F3Bdc40679,
            0xD5930fBF64241267251964616c0654BC8f43eda1,
            0x3CF7b4BDE7ee7FbefD0F20FcddD52e5D449Fd869,
            0xD4627fD6840D8CBe44e39521D39a637191cfAf02,
            0x10103d79Ac194EB0c4cc75742Bda65C18dFf335b,
            0x27b0B4033b6BdCdf12c8d4B86969E3AEe53Ca107,
            0xe18C916DE8798D5B4371cFB18541Fc81f43EFBb0,
            0x59c29943F824A268f28cc83700021D72E184Fc9B,
            0x97F8514E9703A7Fb63118bEFc9C09470516D792A,
            0x42BA76742909Da65D9A432350A15c8ae141ac403,
            0x2a5135b0B28ff84de04f05BeF9528D449453dC48,
            0x3Ece5037b581A8933dc85Ce454951AB2640Bdcb6,
            0x66E987845ce787430344561f1FbA1Dab1a25a6aa,
            0xd5df4bEd806369C5dD4E3eF8495e2F1eaae199e6,
            0x59a016B1ae67dAF23008b59389286236f477a5C8,
            0x9bD7a342706231f092AA3Fb70a35e015E67E8180,
            0x1bb216120E8F939f520C610Bdc3C88aDAc4b06f7,
            0xD67E0A40eF741760Eb3B34DC39ff2A9e8b062932,
            0xfC2c80c80AE6d93bCf4d075cfeD11508E624D0e3,
            0xD9847C4759Eb30773Da4b2Cca30a866Ae85C3EC5,
            0x2eB420F573C2fD96C04526f71D13756100F05b7c,
            0xb399daD33e98BBd5f475ae4eBC376233BF0f5F67,
            0x6bCD66643730128F53aB809c21abAFa3beB1cCdA,
            0x8706D3081dEB8100AB150dB0D48e7927A8C560Aa,
            0xc02a84ce429Be61EdA2A25b79780d3f88C40De8F,
            0x890011DC97F7dfd04B26E14C15211953e6E623bC,
            0x035fA5027049Ad613Bc839181995cC5FC92a7543,
            0x0ecccF9DB9b78B5549eee8A37aCBdB8323F62Da1,
            0xa2873F0B76273177C50E08205EC627850DCf27fA,
            0x0C0a22eb6d026B3202D734E63dee4896c3F459ac,
            0xB152d20362c87546E8fC26D3519a137B0D2fc337,
            0x7b3DBE126CC00fDd3ddf7A1d696843a510392BC3,
            0xB3a371163D6058d29d7c173ccAfBa961b2EdAC40,
            0x3aBE5ecBf9dA9aA9c343ff200E6343024e49ea07,
            0x8814856E5b0F4d48186B13D127310d48cdDA85FE,
            0xa774fFB2A2e28fA61C2aDC32A03102dB19F4CC54,
            0x21Ee7CA092F725289ab184972412B497AD35Eae0,
            0xD85f6DE7014E6851ae2cB266E027ccE789A51423,
            0x6a2b463c30D9cb15C9083e49dc43874a68E60435,
            0x069497ae9e364eD10E77a5845870e49c16Fd8B61,
            0x4359e121D23196bF1e2E0e187ca6CFd24c108A9f,
            0x69ef4Ba56d95E5219985316f975C5300863E2528,
            0x2B475b4a69B87890F39A7A4659B64d044072FEf4,
            0xaDE345a6428b4C8A7Bd2180D5C5507FecAF4ce51,
            0x707A54889242E8744A9Dd944ca3ab38B3C1F5702,
            0xDf3C665bdD83F8e58F89C2EF56d1Aca43F8C57fb,
            0x9CEb46c594D6581CF26BB4032B73FE7e59De61bB,
            0x3fc0F10029b113a187c5817D35dE0f3de2a39ebC,
            0x39DD66CBBCd034596feD59F09E19C74756FCf7f1,
            0x0BAb71cfD67e9F037573b4Adc726cE266e2B1b2c,
            0xab4E30AEC15F0588287b63d045b4d4a4Aa78A367,
            0xaf5Ae7CdAff6f1f457bc88F0989c0AF7f583Ab43,
            0x7f010192d9398a1059f6449F1611FD9cc87D70b4,
            0x299667e0B886bc54b74C6229730c2AA6082c9AF3,
            0x04bE358fF3caf8d18451a96f6dea1518988FBB23,
            0xc814275d8B5e76BD163d10b9A9CC626439b6F39C,
            0x784a1CE9419629d6689d4a416256F4519A04621F,
            0xdF1747B3d5F1959cA3CAf8A58091a085319e4935,
            0xfCdC71520c4b493b01EF8322dF8A7753917933bd,
            0x9FE66a8eb5FDD8a5e8510Cf7140Bd06444E64B0D,
            0xe4c619d30a94fb31b72E7aBB5BE2b874A59f0C3E,
            0x66FD49856e079dc906F7e4C21D0A24C0290dbC11,
            0x5f07edCF840b55A6a896F93050fC082C668A0254,
            0xF989a56c03bce24F39D17Dddd4B30Bd80164f6d8,
            0x4cB75146e98562C9d79b31649C6C739e4DCB7CD5,
            0x551B8c62F961640278506b408a751CC29A3f4471,
            0x71f6537a8c2d148cDA5F2cCd926FDC3Dea2851b4,
            0x1Fbb8D78F133B88B007123721CEA6bB7612d0c03,
            0xB1587895DfaDcAFa6ff2aa248B7CdB27134f47CB,
            0x7cAfe4E1d2B79E98963aFc5C423A98DDdCA92379,
            0xB2cd8b9665A9deF78ef23e27CF64A4E7239Dda68,
            0x41C979164161C8dA1c78E92bC5d38E57D15D0d2e,
            0x9B65a89796D4F4b6a733360454c278Ef4c0a99E7,
            0x77cbA005a99c1910C2CAB1F17A87Eb309aB67e4C,
            0x63db75FEB2E31A803e9EB55D300e22aaA433b972,
            0x542904eB0Fa242FfD26403378F06326a8Ff68524,
            0x02b3E8FF458b57A7Ff0CFbf56e7f06c827526DAa,
            0xFdbB4c04Ca7f30F6d1f5b3E21C94EcF766BdC9F2,
            0x679F76b95Ae9BA4DaA835Cbb5BE8952DBC22c5e5,
            0x9145e8868508C0B7Ed394A38A0C2F78D133c43Ce,
            0xb2A3eC6a90fF47d53F1747617CA1DB6eAe70D4Ab,
            0xD2965eC39C7e6a861c69d8C2d902D0a5EE2097F9,
            0x2e90aF5F41bdf5B0504A5E85D2A50A8b277e932E,
            0x4e3b62C102d775C482e3710A37a8116C34a0F66C,
            0x9fbC0b5B1817b9a33356396994733aB02bE2991C,
            0xdC06D8EaA3dC6C68a447849EDF0897E469386E67,
            0xFb06EAf17200f7072ABA66DDbe778CF165FBBbaD,
            0x13224F6760C29f4Da18ee3Fc5436e64010f0c1b0,
            0xdb28102A19cdc1f25bE8884AcA10990c8A731F2f,
            0x3Dfd4227eC0464f0C8E4b8654d44ddA60AC92ee3,
            0x46D886361d6b7ba0d28080132B6ec70E2e49f332,
            0x08Db6BEaF30b15633dD7E21E2f8C67366660e835,
            0x396F0e55fA33513441d556f84a6eA5c6Fd7d217B,
            0xa8602a68cC58A201201Da6577d509C73670C9134,
            0xfD6b72058eaC03a96A3090C68104Aec5549EE7FA,
            0xDDC9cc6b612C9FFB84f0D4A1c1C5d960b2C4eECF,
            0xa58505143661e7850D9a5b9c90E42fd703cfD30B,
            0xBb4B6bD237D4bbaB70994C063456ee14CdDffc12,
            0xc885A94ca999fb58C835e68Fbc6Eb0f23fcFB6d1,
            0xE656497937B44621CE79b8a596d3bBE47A8c99c4,
            0xA6DA4aa500dB52c2387b6984D4b5B7761a1Efb1B,
            0x042D5C92fe449479BBDA527dE9A3103546218252,
            0x97f773188E4105ca0790B3421191c5baFcEC09c1,
            0xd6863289f0fd6CBA7887ABa81d801D26f45Ed9C5,
            0x4A6012470d98d35EaCEC143eb1ea33D95186aD85,
            0x9eC804a308C6d2BA376353208d86FC2aBCBe98F9,
            0x684d32B2CEA5454087e73a8F9b63c89b0aDD46bB,
            0x9C0f0aeEC38FCbB9710117234692225B9B7c4C11,
            0x8E11827e9bb87d04683Fe08484D3Be4ebCd2b36F,
            0x724FD0E60C12CBE81b29398a68e993c693f68496,
            0xcB6bB7Cb1719a3A8139D5FB100b7088a934C739f,
            0xe0ECfDe1407c5466BB233e53b5d77b4e9EFf7Ce7,
            0xB207C0d1114f11EcfEc1AB0A5bfB1098a99F7003,
            0x0865367A4bcC54aB29109BF80e103f96cD9cCa7c,
            0xe3e8E343B7AaB6b9Ec37FC8D25EdDA1719554bA9,
            0x347Cd347389D2CFc24013cE3FF1914e61124972F,
            0x2E7D92EB55BC6159ca29d737a175Ba653319306B,
            0x7a59FC7CffCaB33DBA04fB01038E2ab7C229Ad60,
            0x990f814fD3262496Da6e15D3e6308e70997c2BBb,
            0xabd6CFe1D3DfEeF22a482CF9fea3B9Dd59E8d989,
            0x8439a3B6ed9cF3771Ba4b91C2812316a209ec194,
            0x55726b149171416e467120110e9Ff707E3bbC69a,
            0xB7cD0c8955B19859F38fb58b583995f8380572C5,
            0x62223bb2a4781c9512E5b78cEf1655D1d9cD216d,
            0x8fEaFd5e0FCefdd2624906c0F913D563306aAe17,
            0xe85d4244E5eC1790c36D8968E5c1B4ee2a557243,
            0xc4c432dDa413Ac8Ec421844703E831985A6833e5,
            0xa21b23e5f07E5E28cB42d09502227Eb75b0B64B5,
            0xd24Ec2701838fC5D0ca674bEA2e83D03F5003E47,
            0x87bAE16156bC919C45944862eC13bEd7a5930211,
            0x56B0704fA7B0a3D68e25200880E5df4EB96Ab68F,
            0xF2eCb9985C57eC5366BC73d46E31D3644363eaf1,
            0x360cEBaC3453204D44032d4E4d2c9896DE48a85c,
            0xA4f2D38dc1d5b748e90d775fD73Ce847874e3a48,
            0x02c61F26387F2594F449d2c2B5a1f96c62881ABa,
            0xB94204d1B1133Bc07D51F264976f4e34dF7587D0,
            0xE85DBB09A699c0543C363c3f6E51ef0049e3edC5,
            0x0B708c4596716e2d9D1A65F2e608FEe3B587E09a,
            0x8e851Ba6cc49378B8E682464A3790C90f701E81a,
            0x5ef8a647A6dE87931a5AAb22Dc654abEEE03aC97,
            0x4E99B2991Ab8306833FE403468dC44515694f638,
            0xcD3671a9598D31F875e5CD7c653ec33A97027eAE,
            0x3faB71254Bac9051988866F61a78370AC03f4Ef8,
            0x61db5495a458CC3534e7D5A56A86603D9cc7E911
        ];

        // user count
        uint256 userCount = users.length;
        // make dynamic
        address[] memory userParam = new address[](userCount);
        // user shares list
        uint256[] memory shares = new uint256[](userCount);
        // assets
        uint256[] memory assets = new uint256[](userCount);
        for (uint256 i = 0; i < userCount; i++) {
            userParam[i] = users[i];
            shares[i] = symVault.balanceOf(users[i]);
            assets[i] = symVault.convertToAssets(shares[i]);
        }
        // upgrade current sym vault
        UltraLRT newImpl = new UltraLRT();
        vm.prank(governance);
        symVault.upgradeTo(address(newImpl));

        // setup migration vault
        vm.prank(governance);
        symVault.setMigrationVault(newSymVault);

        // pause the old vault
        vm.prank(governance);
        symVault.pause();

        // prev tvl
        uint256 prevTvl = symVault.totalAssets();

        // migrate
        vm.prank(governance);
        symVault.migrateToV2(userParam);

        // TODO checks for the assets and shares

        for (uint256 i = 0; i < userCount; i++) {
            assertEq(symVault.balanceOf(users[i]), 0);
            assertApproxEqAbs(newSymVault.convertToAssets(newSymVault.balanceOf(users[i])), assets[i], 10);
        }

        // consolelog
        console2.log("==> prev tvl %s", prevTvl);
        console2.log("==> cur tvl %s", symVault.totalAssets());
        console2.log("==> old vault shares %s", symVault.totalSupply());
        console2.log("==> new tvl %s", newSymVault.totalAssets());
        console2.log("==> new shares %s", newSymVault.totalSupply());

        // assertEq(symVault.totalSupply(), 0);
        // assertEq(symVault.totalAssets(), prevTvl);
    }

    function _skipTestWithdrawalFromEigenLayer() public {
        address operator = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5;
        EigenDelegator delegator = EigenDelegator(address(eigenVault.delegatorQueue(0)));
        console2.log("==> delegator address %s", address(delegator));

        // eigen layer contracts
        IStrategy stEthStrategy = IStrategy(delegator.STAKED_ETH_STRATEGY());
        IStrategyManager strategyManager = IStrategyManager(delegator.STRATEGY_MANAGER());
        IDelegationManager delegationManager = IDelegationManager(delegator.DELEGATION_MANAGER());

        // withdrawable assets
        uint256 delegatorTVL = delegator.totalLockedValue();
        uint256 withdrawableAssets = delegator.withdrawableAssets();

        uint256 withdrawableStEthShares =
            Math.min(stEthStrategy.underlyingToShares(withdrawableAssets), stEthStrategy.shares(address(delegator)));
        // // request withdrawal
        uint256 requestedAssets = eigenVault.totalAssets();
        vm.prank(governance);
        eigenVault.liquidationRequest(requestedAssets);

        uint256 blockNum = block.number;
        // console2.log("====> %s", delegator.totalLockedValue());
        assertApproxEqAbs(delegator.totalLockedValue(), delegatorTVL, 10);

        vm.roll(block.number + 1_000_000);

        // complete withdrawal
        WithdrawalInfo[] memory params = new WithdrawalInfo[](1);
        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawableStEthShares;
        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);

        params[0] = WithdrawalInfo({
            staker: address(delegator),
            delegatedTo: operator,
            withdrawer: address(delegator),
            nonce: 1, // invalid nonce
            startBlock: uint32(blockNum),
            strategies: strategies,
            shares: shares
        });
        // complete withdrawal
        vm.prank(governance);
        delegator.completeWithdrawalRequest(params);
        // withdraw assets
        vm.prank(governance);
        eigenVault.collectDelegatorDebt();
    }

    function testEigenMigration() public {
        // testWithdrawalFromEigenLayer();

        address[53] memory users = [
            0x1688325FEf3B02143bA44880a43DccE339f004c0,
            0x7BFEe91193d9Df2Ac0bFe90191D40F23c773C060,
            0x10F983E2b26Cb9F0732486A5c184ECf6602a52f6,
            0x9482C72Cb018eE03d8c23395038B510ED4e6040C,
            0xC0CdbCD0B24361Df8A888E18D2A3cEDD4CEc948E,
            0xdf5F0C59c3b3471B5Da0Aa8BCdeb7c69C7Ba3370,
            // 0xA6C1c5C0092eA16bdaBad3cEE36e8BF7967e8C20, // escrow
            0xC882A446291394637BdACb0B3128e75609532eA5,
            0x9c813c2fe8aDcA8bCd45a0799af01e5ddE075bd0,
            0xCAE3c3A245F9C1C73F4CAf05F8157d48703801F5,
            0x557373118De50A81CA84884d1f2267231A3b1e94,
            0x158e02e4A130AFD22426bc3cCA06dD346f4f54Ea,
            0xf4F1a05dCF0bfd5b5d6ffcfB1a14e6e71b55b7f3,
            0x4CA76d4F49173bd20454F4FBe8E12C69D4CAE898,
            0x777D6F46FD95D501b3BFA892CeF6Cc298DC2310f,
            0x07d36239dB847659B2634483e6380Fa99CBeC719,
            0xaf5Ae7CdAff6f1f457bc88F0989c0AF7f583Ab43,
            0x48c7e0db3DAd3FE4Eb0513b86fe5C38ebB4E0F91,
            0x2B475b4a69B87890F39A7A4659B64d044072FEf4,
            0x24111d1c953ea7bDE68a614dda8d42238EC87773,
            0x551B8c62F961640278506b408a751CC29A3f4471,
            0x67a0c496E961da0abbFB579F8A41068E57f0e9E0,
            0x684d32B2CEA5454087e73a8F9b63c89b0aDD46bB,
            0x1C01C2bdD462056C15901d96f51ECb722892efa2,
            0x37936Aa15b0A3C032a62EB761E025e6594185837,
            0x56Ad8727754544018ceb22EE0D8B561EC8E61893,
            0x78450F5230475FEeE7ca503EcCAa97BcA43A2B11,
            0xD142F6B957D920BEaFB1e9F5d89db2A5FBf2B1C8,
            0xF989a56c03bce24F39D17Dddd4B30Bd80164f6d8,
            0x842b317bA55A8185e935C51E6EE52137868adBdE,
            0xF87a21Ed06cf319937295dB63934E5A77aD3EA63,
            0xb3d98dd918a6cec01F661702A7feB40178Abd756,
            0x990f814fD3262496Da6e15D3e6308e70997c2BBb,
            0x68940558df8995fD518c487865590446BdADfb68,
            0xA280C7E7ef95F3402235a068E3eE3a5d5F23e5A0,
            0xd24Ec2701838fC5D0ca674bEA2e83D03F5003E47,
            0xEBcC98573c3cd9b5B61900D1304DA938B5036a0d,
            0x360cEBaC3453204D44032d4E4d2c9896DE48a85c,
            0x62223bb2a4781c9512E5b78cEf1655D1d9cD216d,
            0xF795ea805BDcc84d96DC00F18803d6815F799686,
            0xdC09EdF802121fbbECc6C974a3F9ee02025A1C66,
            0x5F50f17BabA19B4e70d3190Ebfd643e9D874d799,
            0x305f2E89d84404d9aD508913603be824C7249238,
            0x08f4D9A058f684382AeBCf9B18e070C139b00c9a,
            0x7853bF4B852c17aE536e5Ab48a9b318Be616A312,
            0x80D6aeD584619E4AC8949578EAB3502661F9f81f,
            0xC4Df5f2125151BFF3a6aA7328529eAE1B9d3cC31,
            0x1Af85b7e0b293D552488eB8764B2170DA949817a,
            0xb2ffD46c47b28b7aBeD6725A0aBedD9409F1a1B0,
            0x4542F2e450E2E4e733CEe3f574513e937005Cc2E,
            0xB5a03c23869d658Bf3aEA5e4E07B7f89110f6a2C,
            0x5f07edCF840b55A6a896F93050fC082C668A0254,
            0xbC6ddE88d724A802da38e241826A50946cd75aaD,
            0x46D886361d6b7ba0d28080132B6ec70E2e49f332
        ];
        uint256 totalUsers = 10;
        // make dynamic
        address[] memory userParam = new address[](totalUsers);
        // user shares list
        uint256[] memory shares = new uint256[](totalUsers);
        // assets
        uint256[] memory assets = new uint256[](totalUsers);

        for (uint256 i = 0; i < totalUsers; i++) {
            userParam[i] = users[i];
            shares[i] = eigenVault.balanceOf(users[i]);
            assets[i] = eigenVault.convertToAssets(shares[i]);
            console2.log("==> user %s shares %s assets %s", users[i], shares[i], assets[i]);
        }

        // upgrade current eigen vault
        UltraLRT newImpl = new UltraLRT();
        vm.prank(governance);
        eigenVault.upgradeTo(address(newImpl));

        // setup migration vault
        vm.prank(governance);
        eigenVault.setMigrationVault(newEigenVault);

        // pause the old vault
        vm.prank(governance);
        eigenVault.pause();

        // migrate
        vm.prank(governance);
        eigenVault.migrateToV2(userParam);

        // TODO checks for the assets and shares

        for (uint256 i = 0; i < totalUsers; i++) {
            assertEq(eigenVault.balanceOf(users[i]), 0);
            assertApproxEqAbs(newEigenVault.convertToAssets(newEigenVault.balanceOf(users[i])), assets[i], 10);
        }
    }
}
