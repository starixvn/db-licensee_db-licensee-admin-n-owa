/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250218@Danny
	DB: DBCUST.bodb_licensee
	Description: Add setting rate ASK Terms:
*/

USE bodb_licensee
GO

declare @PartyId int
select @PartyId = PartyId from dbo.OAS_Party with (nolock) where PartyName = 'ASK' and PartyType = 3

-- insert 3rd Rate by Currency 
insert into dbo.LA_ChargeRateByCurrency(ChargeId, CurrencyID, Rate)
select c.ChargeId, e.ExchangeId, 0.04
from dbo.OAS_ChargeInfo c with (nolock)
	cross join Custdb.dbo.Exchange e with(nolock) 
	left join dbo.LA_ChargeRateByCurrency s with (nolock) on c.ChargeId = s.ChargeId
where c.ProductId = 103
	and c.FromParty in (1235)
	and c.ToParty = @PartyId
	and s.ChargeId is null
	AND e.Code = 'THB'

	
-- insert System Mapping (SystemId = 2: OA)
insert into dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
select c.ChargeId, 2 as SystemId
from dbo.OAS_ChargeInfo c with (nolock)
	left join dbo.LA_ChargeInfo_SystemMapping s with (nolock) on c.ChargeId = s.ChargeId and s.SystemId = 2
where c.ProductId = 103
	and c.FromParty in (1235)
	and c.ToParty = @PartyId
	and s.ChargeId is null

