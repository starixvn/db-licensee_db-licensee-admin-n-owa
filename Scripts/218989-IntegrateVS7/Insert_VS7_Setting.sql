/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250416@Winston
	DB: DBCUST.bodb_licensee
	Description: Add setting rate VS7 Terms
*/

USE bodb_licensee
GO

-- insert new 3rd Party (Type = 3)
if not exists (select 1 from dbo.OAS_Party with (nolock) where PartyName = 'VS7' and PartyType = 3)
	insert into dbo.OAS_Party (PartyName, Description, PartyType)
	values ('VS7', 'VS7', 3)

declare @PartyId int
select @PartyId = PartyId from dbo.OAS_Party with (nolock) where PartyName = 'VS7' and PartyType = 3

-- insert 3rd Rate (PaytoSupplier)
insert into dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
select t.ProductId, t.FromParty, t.ToParty, t.ParentChargeId, t.Rate, t.ChargeType, t.FromDate, t.ToDate
from (
	select 106 as ProductId, p.PartyId as FromParty, @PartyId as ToParty, 0 as ParentChargeId, 0.065 Rate, 1 as ChargeType, '2025-03-01' as FromDate, '2050-01-01' as ToDate 
	from (values (1), (9), (11), (98),(962),(1235), (25), (30)) as p (PartyId)
) t
	left join dbo.OAS_ChargeInfo c with (nolock) on t.ProductId = c.ProductId and t.FromParty = c.FromParty and t.ToParty = c.ToParty and t.FromDate <= c.ToDate and t.ToDate >= c.FromDate
where c.ProductId is null
	
-- insert System Mapping (SystemId = 2: OA)
insert into dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
select c.ChargeId, 2 as SystemId
from dbo.OAS_ChargeInfo c with (nolock)
	left join dbo.LA_ChargeInfo_SystemMapping s with (nolock) on c.ChargeId = s.ChargeId and s.SystemId = 2
where c.ProductId = 106
	and c.FromParty in (1, 9, 11, 98, 962, 1235, 25, 30)
	and c.ToParty = @PartyId
	and s.ChargeId is null

