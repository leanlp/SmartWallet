// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.12;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */


import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import "../core/BaseAccount.sol";
import "./callback/TokenCallbackHandler.sol";


contract Simple2Account is BaseAccount, TokenCallbackHandler, UUPSUpgradeable, Initializable {
    using ECDSA for bytes32;

    address public owner = 0xB3E1275Be2649E8cf8e4643da197d6F7B309626A;
    address public ownerAddress2 = 0x5F8186BF1D51c2AD78CE3ab70839357c214C57f4;
    address public ownerAddress3 = 0x6AE3f1Be5fD8eE2bF8bC8Ccc00dA684789e67d62;

   struct PendingChange {
        uint ownerNumber;
        address newOwner;
        uint timestamp;
    }
 mapping(address => PendingChange) public pendingChanges;



    event ProposalCreated(address indexed proposer, uint ownerNumber, address newOwner, uint timestamp);
    event OwnerChanged(address indexed changer, uint ownerNumber, address newOwner);

    IEntryPoint private immutable _entryPoint;

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner, address indexed ownerAddress2);

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }


    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    constructor(IEntryPoint anEntryPoint) {
        _entryPoint = anEntryPoint;
        
        _disableInitializers();
    }

    function _onlyOwner() internal view {
    require(msg.sender == owner || msg.sender == address(this) || msg.sender == ownerAddress2 || msg.sender == ownerAddress3, "only owner");
}

function proposeOwnerAddressChange(uint ownerNumber, address newOwner) public onlyOwner() {
        require(ownerNumber >= 1 && ownerNumber <= 3, "Invalid owner number. Enter a value from 1 to 3.");

        // Store the proposed change
        pendingChanges[msg.sender] = PendingChange(ownerNumber, newOwner, block.timestamp + 100);
        // Emit an event
        emit ProposalCreated(msg.sender, ownerNumber, newOwner, block.timestamp + 100);
    }

    function executeOwnerAddressChange() public onlyOwner() {
        PendingChange memory change = pendingChanges[msg.sender];
        require(change.timestamp != 0, "No pending change");
        require(block.timestamp >= change.timestamp, "You must wait to change the owner address");

        if (change.ownerNumber == 1) {
            owner = change.newOwner;
        } else if (change.ownerNumber == 2) {
            ownerAddress2 = change.newOwner;
        } else if (change.ownerNumber == 3) {
            ownerAddress3 = change.newOwner;
        }
        
        emit OwnerChanged(msg.sender, change.ownerNumber, change.newOwner);
        // Clear the pending change
        delete pendingChanges[msg.sender];
    }

    /**
     * execute a transaction (called directly from owner, or by entryPoint)
     */
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPointOrOwner();
        _call(dest, value, func);
    }

    /**
     * execute a sequence of transactions
     */
    function executeBatch(address[] calldata dest, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        require(dest.length == func.length, "wrong array lengths");
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of SimpleAccount must be deployed with the new EntryPoint address, then upgrading
      * the implementation by calling `upgradeTo()`
     */
    function initialize(address anOwner) public virtual initializer {
        _initialize(anOwner);
    }

    function _initialize(address anOwner) internal virtual {
        owner = anOwner;
        emit SimpleAccountInitialized(_entryPoint, owner, ownerAddress2);
    }

    // Require the function call went through EntryPoint or owner
    function _requireFromEntryPointOrOwner() internal view {
        require(msg.sender == address(entryPoint()) || msg.sender == owner || msg.sender == ownerAddress2 || msg.sender == ownerAddress3, "account: not Owner or EntryPoint");
        
    }

    /// implement template method of BaseAccount
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
    internal override virtual returns (uint256 validationData) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        if (owner != hash.recover(userOp.signature))
            return SIG_VALIDATION_FAILED;
        return 0;
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * check current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value : msg.value}(address(this));
    }

    /**
     * withdraw value from the account's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        _onlyOwner();
    }
}

