/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20210811@Percy
	DB: DBCUST-bodb_Licensee
	Task: Insert charge rate for BitCoin
	ProductId = 69
*/
use bodb_Licensee
go

-- insert new 3rd Party (Type = 3)
if not exists (select 1 from dbo.OAS_Party with (nolock) where PartyName = 'BTC' and PartyType = 3)
	insert into dbo.OAS_Party (PartyName, Description, PartyType)
	values ('BTC', 'Bitcoin', 3)

declare @PartyId int
select @PartyId = PartyId from dbo.OAS_Party with (nolock) where PartyName = 'BTC' and PartyType = 3

-- insert 3rd Rate (PaytoSupplier)
insert into dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
select t.ProductId, t.FromParty, t.ToParty, t.ParentChargeId, t.Rate, t.ChargeType, t.FromDate, t.ToDate
from (
	select 69 as ProductId, p.PartyId as FromParty, @PartyId as ToParty, 0 as ParentChargeId, 0.02 as Rate, 1 as ChargeType, '2021-09-30' as FromDate, '2050-01-01' as ToDate 
	from (values (1), (9), (11), (98), (25), (30)) as p (PartyId)
) t
	left join dbo.OAS_ChargeInfo c with (nolock) on t.ProductId = c.ProductId and t.FromParty = c.FromParty and t.ToParty = c.ToParty and t.FromDate <= c.ToDate and t.ToDate >= c.FromDate
where c.ProductId is null
	
-- insert System Mapping (SystemId = 2: OA)
insert into dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
select c.ChargeId, 2 as SystemId
from dbo.OAS_ChargeInfo c with (nolock)
	left join dbo.LA_ChargeInfo_SystemMapping s with (nolock) on c.ChargeId = s.ChargeId and s.SystemId = 2
where c.ProductId = 69
	and c.FromParty in (1, 9, 11, 98, 25, 30)
	and c.ToParty = @PartyId
	and s.ChargeId is null