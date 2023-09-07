/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20230825@Danny
	DB: DBCUST-bodb_Licensee
	Task: Insert 3rd charge rate for Exchange
	ProductId = 31
*/
use bodb_Licensee
go

declare @PartyId int
select @PartyId = PartyId from dbo.OAS_Party with (nolock) where PartyName = 'Exchange' and PartyType = 3


-- insert 3rd Rate (PaytoSupplier)
insert into dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
select t.ProductId, t.FromParty, t.ToParty, t.ParentChargeId, t.Rate, t.ChargeType, t.FromDate, t.ToDate
from (
	select 31 as ProductId, p.PartyId as FromParty, @PartyId as ToParty, 0 as ParentChargeId, 0.1 as Rate, 1 as ChargeType, '2023-08-01' as FromDate, '2050-01-01' as ToDate 
	from (values (9), (11), (98)) as p (PartyId)
) t
	left join dbo.OAS_ChargeInfo c with (nolock) on t.ProductId = c.ProductId and t.FromParty = c.FromParty and t.ToParty = c.ToParty and t.FromDate <= c.ToDate and t.ToDate >= c.FromDate
where c.ProductId is null
	
-- insert System Mapping (SystemId = 2: OA)
insert into dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
select c.ChargeId, 2 as SystemId
from dbo.OAS_ChargeInfo c with (nolock)
	left join dbo.LA_ChargeInfo_SystemMapping s with (nolock) on c.ChargeId = s.ChargeId and s.SystemId = 2
where c.ProductId = 31
	and c.FromParty in (9, 11, 98)
	and c.ToParty = @PartyId
	and s.ChargeId is null
