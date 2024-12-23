/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20241223@Danny
	DB: DBCUST.bodb_licensee
	Description: Add setting rate On PPL Terms:
*/

USE bodb_licensee
GO
-- End Old setting 
DECLARE @PPL_PartyId INT

SELECT @PPL_PartyId = PartyID FROM OAS_party WITH(NOLOCK) WHERE PartyType = 3 AND  PartyName = 'PPL'

UPDATE  OAS_ChargeInfo WITH(ROWLOCK, UPDLOCK) 
SET ToDate = '2024-11-30'
WHERE ToParty = @PPL_PartyId AND ProductID = 65 AND FromDate <= '2024-11-30' AND ToDate >= '2024-11-30'



-- insert new 3rd Rate (PaytoSupplier)
insert into dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
select t.ProductId, t.FromParty, t.ToParty, t.ParentChargeId, t.Rate, t.ChargeType, t.FromDate, t.ToDate
from (
	select 65 as ProductId, p.PartyId as FromParty, @PPL_PartyId as ToParty, 0 as ParentChargeId, 0.065 Rate, 1 as ChargeType, '2024-12-01' as FromDate, '2050-01-01' as ToDate 
	from (values (25), (30)) as p (PartyId)
) t

insert into dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
select t.ProductId, t.FromParty, t.ToParty, t.ParentChargeId, t.Rate, t.ChargeType, t.FromDate, t.ToDate
from (
	select 65 as ProductId, p.PartyId as FromParty, @PPL_PartyId as ToParty, 0 as ParentChargeId, 0.005 Rate, 11 as ChargeType, '2024-12-01' as FromDate, '2050-01-01' as ToDate 
	from (values (25), (30)) as p (PartyId)
) t


-- insert System Mapping (SystemId = 2: OA)
insert into dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
select c.ChargeId, 2 as SystemId
from dbo.OAS_ChargeInfo c with (nolock)
	left join dbo.LA_ChargeInfo_SystemMapping s with (nolock) on c.ChargeId = s.ChargeId and s.SystemId = 2
where c.ProductId = 65
	and c.FromParty in (25, 30)
	and c.ToParty = @PPL_PartyId
	and s.ChargeId is null

