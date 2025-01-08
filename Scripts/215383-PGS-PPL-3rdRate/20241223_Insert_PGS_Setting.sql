/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20241223@Danny
	DB: DBCUST.bodb_licensee
	Description: Add setting rate On PGS Terms:
*/

USE bodb_licensee
GO

DECLARE @PGS_PartyId INT
SELECT @PGS_PartyId = PartyID FROM OAS_party WITH(NOLOCK) WHERE PartyType = 3 AND  PartyName = 'PGS'

-- End Old setting 
UPDATE  OAS_ChargeInfo WITH(ROWLOCK, UPDLOCK) 
SET ToDate = '2024-11-30'
WHERE ToParty = @PGS_PartyId AND ProductID = 55 AND FromDate <= '2024-11-30' AND ToDate >= '2024-11-30'


-- insert new 3rd Rate (PaytoSupplier)
insert into dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
select t.ProductId, t.FromParty, t.ToParty, t.ParentChargeId, t.Rate, t.ChargeType, t.FromDate, t.ToDate
from (
	select 55 as ProductId, p.PartyId as FromParty, @PGS_PartyId as ToParty, 0 as ParentChargeId, 0.04 Rate, 1 as ChargeType, '2024-12-01' as FromDate, '2050-01-01' as ToDate 
	from (values (1), (9), (11), (98),(962), (25), (30)) as p (PartyId)
) t
	left join dbo.OAS_ChargeInfo c with (nolock) on t.ProductId = c.ProductId and t.FromParty = c.FromParty and t.ToParty = c.ToParty and t.FromDate <= c.ToDate and t.ToDate >= c.FromDate
where c.ProductId is null


-- insert 3rd Rate by Currency 
insert into dbo.LA_ChargeRateByCurrency(ChargeId, CurrencyID, Rate)
select c.ChargeId, e.ExchangeId, 0.09
from dbo.OAS_ChargeInfo c with (nolock)
	cross join Custdb.dbo.Exchange e with(nolock) 
	left join dbo.LA_ChargeRateByCurrency s with (nolock) on c.ChargeId = s.ChargeId
where c.ProductId = 55
	and c.FromParty in (1, 9, 11, 98, 962, 25, 30)
	and c.ToParty = @PGS_PartyId
	and s.ChargeId is null
	AND e.Code = 'THB'
	AND c.FromDate >= '2024-12-01'

-- insert System Mapping (SystemId = 2: OA)
insert into dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
select c.ChargeId, 2 as SystemId
from dbo.OAS_ChargeInfo c with (nolock)
	left join dbo.LA_ChargeInfo_SystemMapping s with (nolock) on c.ChargeId = s.ChargeId and s.SystemId = 2
where c.ProductId = 55
	and c.FromParty in (1, 9, 11, 98, 962, 25, 30)
	and c.ToParty = @PGS_PartyId
	and s.ChargeId is null