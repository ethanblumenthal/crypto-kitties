// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./Ownable.sol";

abstract contract CryptoKitties is IERC721, Ownable {

    uint256 public constant CREATION_LIMIT_GEN0 = 10;
    string public override constant name = "CryptoKitties";
    string public override constant symbol = "CK";

    bytes4 internal constant MAGIC_ERC721_RECEIVED = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));

    /*
     *     bytes4(keccak256('balanceOf(address)')) == 0x70a08231
     *     bytes4(keccak256('ownerOf(uint256)')) == 0x6352211e
     *     bytes4(keccak256('approve(address,uint256)')) == 0x095ea7b3
     *     bytes4(keccak256('getApproved(uint256)')) == 0x081812fc
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c5
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     => 0x70a08231 ^ 0x6352211e ^ 0x095ea7b3 ^ 0x081812fc ^
     *        0xa22cb465 ^ 0xe985e9c ^ 0x23b872dd ^ 0x42842e0e ^ 0xb88d4fde == 0x80ac58cd
     */
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    /*
     *     bytes4(keccak256('supportsInterface(bytes4)'));
     */
    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;

    event Birth(address owner, uint256 kittenId, uint256 momId, uint256 dadId, uint256 genes);

    struct Kitty {
        uint256 genes;
        uint64 birthTime;
        uint32 momId;
        uint32 dadId;
        uint16 generation;
    }

    Kitty[] kitties;

    mapping (uint256 => address) public kittyIndexToOwner;
    mapping (address => uint256) ownershipTokenCount;
    mapping (uint256 => address) public kittyIndexToApproved;
    mapping (address => mapping (address => bool)) private _operatorApprovals;

    uint256 gen0Counter;

    function breed(uint256 _dadId, uint256 _momId) public returns (uint256){
        require(_owns(msg.sender, _dadId), "The user doesn't own the token");
        require(_owns(msg.sender, _momId), "The user doesn't own the token");

        ( uint256 dadDna,,,,uint256 DadGeneration ) = getKitty(_dadId);

        ( uint256 momDna,,,,uint256 MomGeneration ) = getKitty(_momId);
        
        uint256 newDna = _mixDna(dadDna, momDna);

        uint256 kidGen = 0;
        if (DadGeneration < MomGeneration) {
            kidGen = MomGeneration + 1;
            kidGen /= 2;
        } else if (DadGeneration > MomGeneration) {
            kidGen = DadGeneration + 1;
            kidGen /= 2;
        } else {
            kidGen = MomGeneration + 1;
        }

        _createKitty(_momId, _dadId, kidGen, newDna, msg.sender);

    }

    function supportsInterface(bytes4 _interfaceId) external view returns (bool) {
        return (_interfaceId == _INTERFACE_ID_ERC721 || _interfaceId == _INTERFACE_ID_ERC165);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) public override {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory _data) public override {
        require( _isApprovedOrOwner(msg.sender, _from, _to, _tokenId) );
        _safeTransfer(_from, _to, _tokenId, _data);
    }

    function _safeTransfer(address _from, address _to, uint256 _tokenId, bytes memory _data) internal {
        require(_checkERC721Support(_from, _to, _tokenId, _data));
        _transfer(_from, _to, _tokenId);
    }

    function transferFrom(address _from, address _to,uint256 _tokenId) public override {
        require( _isApprovedOrOwner(msg.sender, _from, _to, _tokenId) );
        _transfer(_from, _to, _tokenId);
    }

    function approve(address _to, uint256 _tokenId) public override {
        require(_owns(msg.sender, _tokenId));

        _approve(_tokenId, _to);
        emit Approval(msg.sender, _to, _tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public override {
        require(operator != msg.sender);

        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    
    function getApproved(uint256 tokenId) public view override returns (address) {
        require(tokenId < kitties.length); // Token must exist
        return kittyIndexToApproved[tokenId];
    }
    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function getKitty(uint256 _id) public view returns (uint256 genes, uint256 birthTime, uint256 momId, uint256 dadId, uint256 generation) {
        Kitty storage kitty = kitties[_id];

        genes = uint256(kitty.genes);
        birthTime = uint256(kitty.birthTime);
        momId = uint256(kitty.momId);
        dadId = uint256(kitty.dadId);
        generation = uint256(kitty.generation);

    }

    function createKittyGen0(uint256 _genes) public onlyOwner returns (uint256) {
        require(gen0Counter < CREATION_LIMIT_GEN0);

        gen0Counter++;

        // Gen0 have no owners as they are owned by the contract
        return _createKitty(0, 0, 0, _genes, msg.sender);
    }

    function _createKitty(uint256 _momId, uint256 _dadId, uint256 _generation, uint256 _genes, address _owner) private returns (uint256) {
        Kitty memory _kitty = Kitty({
            genes: _genes,
            birthTime: uint64(block.timestamp),
            momId: uint32(_momId),
            dadId: uint32(_dadId),
            generation: uint16(_generation)
        });

        uint256 newKittenId = kitties.push(_kitty) - 1;
        emit Birth(_owner, newKittenId, _momId, _dadId, _genes);
        _transfer(address(0), _owner, newKittenId);

        return newKittenId;
    }

    function balanceOf(address owner) external view override returns (uint256 balance) {
        return ownershipTokenCount[owner];
    }

    function totalSupply() public view override returns (uint) {
        return kitties.length;
    }

    function ownerOf(uint256 _tokenId) external view override returns (address) {
        return kittyIndexToOwner[_tokenId];
    }

    function transfer(address _to, uint256 _tokenId) external override {
        require(_to != address(0));
        require(_to != address(this));
        require(_owns(msg.sender, _tokenId));

        _transfer(msg.sender, _to, _tokenId);
    }

    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        ownershipTokenCount[_to]++;
        kittyIndexToOwner[_tokenId] = _to;

        if (_from != address(0)) {
            ownershipTokenCount[_from]--;
            delete kittyIndexToApproved[_tokenId];
        }

        // Emit the transfer event
        emit Transfer(_from, _to, _tokenId);
    }

    function _owns(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return kittyIndexToOwner[_tokenId] == _claimant;
    }

    function _approve(uint256 _tokenId, address _approved) internal {
        kittyIndexToApproved[_tokenId] = _approved;
    }

    function _approvedFor(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return kittyIndexToApproved[_tokenId] == _claimant;
    }

    function _checkERC721Support(address _from, address _to, uint256 _tokenId, bytes memory _data) internal returns (bool) {
        if( !_isContract(_to) ){
            return true;
        }

        bytes4 returnData = IERC721Receiver(_to).onERC721Received(msg.sender, _from, _tokenId, _data);
        return returnData == MAGIC_ERC721_RECEIVED;
    }

    function _isContract(address _to) internal view returns (bool) {
        uint32 size;
        assembly{
            size := extcodesize(_to)
        }
        return size > 0;
    }

    function _isApprovedOrOwner(address _spender, address _from, address _to, uint256 _tokenId) internal view returns (bool) {
        require(_tokenId < kitties.length); // Token must exist
        require(_to != address(0)); // TO address is not zero address
        require(_owns(_from, _tokenId)); // From owns the token
        
        // Spender is from OR spender is approved for tokenId OR spender is operator for from
        return (_spender == _from || _approvedFor(_spender, _tokenId) || isApprovedForAll(_from, _spender));
    }

 function _mixDna(uint256 _dadDna, uint256 _momDna) internal returns (uint256) {
        // dadDna: 11 22 33 44 55 66 77 88 
        // momDna: 88 77 66 55 44 33 22 11

        uint256 firstHalf = _dadDna / 100000000; // 11 22 33 44
        uint256 secondHalf = _momDna % 100000000; // 88 77 66 55
        
        uint256 newDna = firstHalf * 100000000;
        newDna = newDna + secondHalf; // 11 22 33 44 88 77 66 55
        return newDna;
    }
}