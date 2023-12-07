// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "foundry-huff/HuffDeployer.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/lib/BytecodeDeployer.sol";
import {MockNFTNonHolder} from "../src/test/MockNFTNonHolder.sol";
import {MockNFTHolder} from "../src/test/MockNFTHolder.sol";
import {MockNFTBuggyHolder} from "../src/test/MockNFTBuggyHolder.sol";

uint256 constant TOKEN_ID = 0;
address constant user2 = address(1);
address constant user3 = address(2);
address constant zeroAddress = address(0);

interface Huff721 {
    function name() view external returns (string memory);
    function symbol() view external returns (string memory);
    function supportsInterface(bytes4) view external returns (bool);
    function balanceOf(address) view external returns (uint256);
    function mint() external;
    function ownerOf(uint256) external returns (address);
    function nextId() external returns (uint256);
    function totalSupply() external returns (uint256);
    function transferFrom(address, address, uint256) external;
    function safeTransferFrom(address, address, uint256) external;
    function safeTransferFrom(address, address, uint256, bytes calldata) external;
    function approve(address, uint256) external;
    function getApproved(uint256) external returns (address);
    function isApprovedForAll(address, address) external returns (bool);
    function setApprovalForAll(address, bool) external;

    error ERC721NonexistentToken(uint256 tokenId);
    error ERC721InvalidReceiver(address receiver);
    error ERC721AccessDenied();
    error ERC721InvalidAddress(address receiver);
    error ERC721MintLimit();
    error ERC721MaxSupplyLimit();
}

contract BaseTest is Test {
    Huff721 public huff;
    BytecodeDeployer bytecodeDeployer = new BytecodeDeployer();
    address me;
    address nftNonHolder;
    address nftHolder;
    address nftBuggyHolder;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function setUp() public virtual {
        huff = Huff721(bytecodeDeployer.deployContract("Huff721"));
        me = address(this);
        nftNonHolder = address(new MockNFTNonHolder());
        nftHolder = address(new MockNFTHolder());
        nftBuggyHolder = address(new MockNFTBuggyHolder());
    }
}

contract AttributesTest is BaseTest {
    function testAttributes() public {
        assertEq("Huff 721", huff.name());
        assertEq("HUFF", huff.symbol());
      }
}

contract SupportsInterfaceTest is BaseTest {
    // returns true for supported interfaces
    function test_supportedInterfaces() public {
        assertTrue(huff.supportsInterface(0x01ffc9a7));
        assertTrue(huff.supportsInterface(0x80ac58cd));
    }

    // returns false for not supported interfaces
    function test_notSupportedInterfaces() public {
        assertFalse(huff.supportsInterface(0x12121212));
    }
}

contract BalanceOfTest is BaseTest {
    // returns correct balances
    function test_balanceOf() public {
        assertEq(huff.balanceOf(user2), 0);
        vm.startPrank(user2);
        huff.mint();
        assertEq(huff.balanceOf(user2), 1);
        huff.mint();
        assertEq(huff.balanceOf(user2), 2);
    }

    // balanceOf the zero address
    function test_balanceOfZero() public {
        vm.expectRevert(abi.encodeWithSelector(Huff721.ERC721InvalidAddress.selector, zeroAddress));
        huff.balanceOf(zeroAddress);
    }
}

contract MintTest is BaseTest {
    // mints an NFT token to the target account
    function test_mintTarget() public {
        huff.mint();
        assertEq(huff.ownerOf(TOKEN_ID), me);
        huff.mint();
        assertEq(huff.balanceOf(me), 2);
    }

    // increments totalSupply and nextId
    function test_incrementCounters() public {
        uint256 nextIdBefore = huff.nextId();
        assertEq(nextIdBefore, 0);

        uint256 totalSupplyBefore = huff.totalSupply();
        assertEq(totalSupplyBefore, 0);

        huff.mint();

        uint256 nextIdAfter = huff.nextId();
        assertEq(nextIdAfter, 1);

        uint256 totalSupplyAfter = huff.totalSupply();
        assertEq(totalSupplyAfter, 1);
    }

    // has working maxSupply limit
    function test_maxSupply() public {
        for (uint256 i = 0; i < 1024; i++) {
            vm.prank(address(uint160(i)));
            huff.mint();
        }

        vm.expectRevert(Huff721.ERC721MaxSupplyLimit.selector);
        huff.mint();
    }

    // can only be executed twice by each address
    function test_maxMintLimit() public {
        huff.mint();
        huff.mint();
        vm.expectRevert(Huff721.ERC721MintLimit.selector);
        huff.mint();
    }

    // emits a correct event
    function test_emitEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(zeroAddress, me, TOKEN_ID);
        huff.mint();
    }
}

contract TransferFromTest is BaseTest {
    function setUp() public override {
        super.setUp();
        huff.mint();
    }

    // changes owner of a correct NFT token
    function test_changesOwner() public {
        address ownerBefore = huff.ownerOf(TOKEN_ID);
        assertEq(ownerBefore, me);

        uint256 balanceBefore = huff.balanceOf(me);
        assertEq(balanceBefore, 1);

        huff.transferFrom(me, user2, TOKEN_ID);

        address ownerAfter = huff.ownerOf(TOKEN_ID);
        assertEq(ownerAfter, user2);

        uint256 balanceAfter = huff.balanceOf(me);
        assertEq(balanceAfter, 0);

        uint256 otherBalanceAfter = huff.balanceOf(user2);
        assertEq(otherBalanceAfter, 1);
    }

    // emits a correct Transfer event
    function test_emitsTransferEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(me, user2, TOKEN_ID);
        huff.transferFrom(me, user2, TOKEN_ID);
    }

    function test_transferringTokensNotYourOwn() public {
        vm.prank(user2);
        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        huff.transferFrom(me, user2, TOKEN_ID);
    }

    // 'transferFrom(address,address,uint256)' token to the zero address
    function test_transferFromToZero() public {
        vm.expectRevert(abi.encodeWithSelector(Huff721.ERC721InvalidAddress.selector, zeroAddress));
        huff.transferFrom(me, zeroAddress, TOKEN_ID);
    }
}

contract SafeTransferFromTest is BaseTest {
    function setUp() public override {
        super.setUp();
        huff.mint();
        huff.mint();
    }

    // changes owner of a correct NFT token
    function test_changesOwner() public {
        address ownerBefore = huff.ownerOf(TOKEN_ID);
        assertEq(ownerBefore, me);

        uint256 balanceBefore = huff.balanceOf(me);
        assertEq(balanceBefore, 2);

        huff.safeTransferFrom(me, user2, TOKEN_ID);

        address ownerAfter = huff.ownerOf(TOKEN_ID);
        assertEq(ownerAfter, user2);

        uint256 balanceAfter = huff.balanceOf(me);
        assertEq(balanceAfter, 1);
    }

    // does not allow transferring token that an address does not own
    function test_transferringTokensNotYourOwn() public {
        vm.prank(user2);
        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        huff.safeTransferFrom(me, user2, TOKEN_ID);
    }

    // emits a correct Transfer event
    function test_emitsTransferEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(me, user2, TOKEN_ID);
        huff.safeTransferFrom(me, user2, TOKEN_ID);
    }

    // will not transfer NFT to contract which does not implement 'onERC721Received' callback
    function test_transferToNFTNonHolder() public {
        vm.expectRevert(abi.encodeWithSelector(Huff721.ERC721InvalidReceiver.selector, nftNonHolder));

        huff.safeTransferFrom(me, nftNonHolder, TOKEN_ID);
    }

    // it transfers NFT to contract which implements a correct 'onERC721Received' callback
    function test_transferToNFTHolder() public {
        vm.breakpoint('a');
        huff.safeTransferFrom(me, nftHolder, TOKEN_ID);
        assertEq(huff.ownerOf(TOKEN_ID), nftHolder);
    }

    // will not transfer NFT to contract which implements incorrect 'onERC721Received' callback
    function test_transferToNFTBuggyHolder() public {
        vm.expectRevert(abi.encodeWithSelector(Huff721.ERC721InvalidReceiver.selector, nftBuggyHolder));

        huff.safeTransferFrom(me, nftBuggyHolder, TOKEN_ID);
    }

    // 'safeTransferFrom(address,address,uint256)' token to the zero address
    function test_transferFromToZero() public {
        vm.expectRevert(abi.encodeWithSelector(Huff721.ERC721InvalidAddress.selector, zeroAddress));
        huff.safeTransferFrom(me, zeroAddress, TOKEN_ID);
    }
}

contract SafeTransferFromBytesTest is BaseTest {
    function setUp() public override {
        super.setUp();
        huff.mint();
        huff.mint();
    }

    // changes owner of a correct NFT token
    function test_changesOwner() public {
        address ownerBefore = huff.ownerOf(TOKEN_ID);
        assertEq(ownerBefore, me);

        uint256 balanceBefore = huff.balanceOf(me);
        assertEq(balanceBefore, 2);

        huff.safeTransferFrom(me, user2, TOKEN_ID, "");

        // address ownerAfter = huff.ownerOf(TOKEN_ID);
        // assertEq(ownerAfter, user2);

        uint256 balanceAfter = huff.balanceOf(me);
        assertEq(balanceAfter, 1);
    }

    // does not allow transferring token that an address does not own
    function test_transferringTokensNotYourOwn() public {
        vm.prank(user2);
        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        huff.safeTransferFrom(me, user2, TOKEN_ID, "");
    }

    // emits a correct Transfer event
    function test_emitsTransferEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(me, user2, TOKEN_ID);
        huff.safeTransferFrom(me, user2, TOKEN_ID, "");
    }

    // will not transfer NFT to contract which does not implement 'onERC721Received' callback
    function test_transferToNFTNonHolder() public {
        vm.expectRevert(abi.encodeWithSelector(Huff721.ERC721InvalidReceiver.selector, nftNonHolder));

        huff.safeTransferFrom(me, nftNonHolder, TOKEN_ID, "");
    }

    // it transfers NFT to contract which implements a correct 'onERC721Received' callback
    function test_transferToNFTHolder() public {
        huff.safeTransferFrom(me, nftHolder, TOKEN_ID, "");
        assertEq(huff.ownerOf(TOKEN_ID), nftHolder);
    }

    // will not transfer NFT to contract which implements incorrect 'onERC721Received' callback
    function test_transferToNFTBuggyHolder() public {
        vm.expectRevert(abi.encodeWithSelector(Huff721.ERC721InvalidReceiver.selector, nftBuggyHolder));

        huff.safeTransferFrom(me, nftBuggyHolder, TOKEN_ID, "");
    }

    // 'safeTransferFrom(address,address,uint256,bytes)' token to the zero address
    function test_transferFromToZero() public {
        vm.expectRevert(abi.encodeWithSelector(Huff721.ERC721InvalidAddress.selector, zeroAddress));
        huff.safeTransferFrom(me, zeroAddress, TOKEN_ID, "");
    }
}

contract ApproveTest is BaseTest {
    function setUp() public override {
        super.setUp();
        huff.mint();
        huff.mint();
    }

    // emits a correct event
    function test_emitEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(me, user2, TOKEN_ID);
        huff.approve(user2, TOKEN_ID);
    }

    // grants other account permission to transfer only a target token for 'transferFrom(address,address,uint256)'
    function test_approveTransferFrom() public {
        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        vm.prank(user2);
        huff.transferFrom(me, user2, TOKEN_ID);

        huff.approve(user2, TOKEN_ID);

        vm.prank(user2);
        huff.transferFrom(me, user2, TOKEN_ID);

        assertEq(huff.ownerOf(TOKEN_ID), user2);

        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        vm.prank(user2);
        huff.transferFrom(me, user2, TOKEN_ID + 1);
    }

    // grants other account permission to transfer only a target token for 'safeTransferFrom(address,address,uint256)'
    function test_approveSafeTransferFrom() public {
        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        vm.prank(user2);
        huff.safeTransferFrom(me, user2, TOKEN_ID);

        huff.approve(user2, TOKEN_ID);

        vm.prank(user2);
        huff.safeTransferFrom(me, user2, TOKEN_ID);

        assertEq(huff.ownerOf(TOKEN_ID), user2);

        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        vm.prank(user2);
        huff.safeTransferFrom(me, user2, TOKEN_ID + 1);
    }

    // grants other account permission to transfer only a target token for 'safeTransferFrom(address,address,uint256,bytes)'
    function test_approveSafeTransferFromBytes() public {
        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        vm.prank(user2);
        huff.safeTransferFrom(me, user2, TOKEN_ID, "");

        huff.approve(user2, TOKEN_ID);

        vm.prank(user2);
        huff.safeTransferFrom(me, user2, TOKEN_ID, "");

        assertEq(huff.ownerOf(TOKEN_ID), user2);

        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        vm.prank(user2);
        huff.safeTransferFrom(me, user2, TOKEN_ID + 1, "");
    }

    // can be called only be an account owning a target token
    function test_approveOnlyByOwner() public {
        huff.approve(user2, TOKEN_ID);

        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        vm.prank(user2);
        huff.approve(user3, TOKEN_ID);
    }
}

contract GetApprovedTest is BaseTest {
    function setUp() public override {
        super.setUp();
        huff.mint();
    }

    // throws an error for non-existent token
    function test_nonExistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(Huff721.ERC721NonexistentToken.selector, TOKEN_ID + 1));
        huff.getApproved(TOKEN_ID + 1);
    }

    // returns address approved as a target token operator
    function test_returnsAddress() public {
        huff.approve(user2, TOKEN_ID);
        assertEq(huff.getApproved(TOKEN_ID), user2);
    }
}

contract SetApprovalForAllTest is BaseTest {
    function setUp() public override {
        super.setUp();
        huff.mint();
        huff.mint();
    }

    // emits a correct event
    function test_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit ApprovalForAll(me, user2, true);
        huff.setApprovalForAll(user2, true);

        vm.expectEmit(true, true, false, true);
        emit ApprovalForAll(me, user2, false);
        huff.setApprovalForAll(user2, false);
    }

    // grants target operator a permission to transferFrom(address,address,uint256) all the tokens and can be reverted
    function test_permissionForTransferFrom() public {
        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        vm.prank(user2);
        huff.transferFrom(me, user2, TOKEN_ID);

        huff.setApprovalForAll(user2, true);

        vm.prank(user2);
        vm.breakpoint('a');
        huff.transferFrom(me, user2, TOKEN_ID);
        assertEq(huff.balanceOf(user2), 1);

        huff.setApprovalForAll(user2, false);

        vm.expectRevert(Huff721.ERC721AccessDenied.selector);
        vm.prank(user2);
        huff.transferFrom(me, user2, TOKEN_ID + 1);
    }
}

contract IsApprovedForAllTest is BaseTest {
    function setUp() public override {
        super.setUp();
        huff.mint();
    }

    // returns address bool indicating if target account is approved for all tokens management as a target token operator
    function test_returnsBool() public {
        vm.breakpoint('a');
        bool beforeApproval = huff.isApprovedForAll(me, user2);
        assertFalse(beforeApproval);

        huff.setApprovalForAll(user2, true);

        bool afterApproval = huff.isApprovedForAll(me, user2);
        assertTrue(afterApproval);
    }
}

contract EdgeCasesTest is BaseTest {
    function setUp() public override {
        super.setUp();
        huff.mint();
        huff.mint();
    }

    // 'transferFrom(address,address,uint256)' token to the zero address
    function test_transferFromToZero() public {
        vm.expectRevert(abi.encodeWithSelector(Huff721.ERC721InvalidAddress.selector, zeroAddress));
        huff.safeTransferFrom(me, zeroAddress, TOKEN_ID);
    }
}
