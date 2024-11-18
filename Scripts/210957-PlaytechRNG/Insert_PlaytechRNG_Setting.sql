/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240927@Danny
	DB: DBCUST.bodb_licensee
	Description: Add setting rate Playtech Terms:
*/

USE bodb_licensee
GO

-- insert new 3rd Party (Type = 3)
if not exists (select 1 from dbo.OAS_Party with (nolock) where PartyName = 'PTRNG' and PartyType = 3)
	insert into dbo.OAS_Party (PartyName, Description, PartyType)
	values ('PTRNG', 'Playtech', 3)

declare @PartyId int
select @PartyId = PartyId from dbo.OAS_Party with (nolock) where PartyName = 'PTRNG' and PartyType = 3

-- insert 3rd Rate (PaytoSupplier)
insert into dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
select t.ProductId, t.FromParty, t.ToParty, t.ParentChargeId, t.Rate, t.ChargeType, t.FromDate, t.ToDate
from (
	select 100 as ProductId, p.PartyId as FromParty, @PartyId as ToParty, 0 as ParentChargeId, 0.06 Rate, 1 as ChargeType, '2024-11-19' as FromDate, '2050-01-01' as ToDate 
	from (values (1), (9), (11), (98),(962), (25), (30)) as p (PartyId)
) t
	left join dbo.OAS_ChargeInfo c with (nolock) on t.ProductId = c.ProductId and t.FromParty = c.FromParty and t.ToParty = c.ToParty and t.FromDate <= c.ToDate and t.ToDate >= c.FromDate
where c.ProductId is null


-- insert 3rd Rate by Currency 
insert into dbo.LA_ChargeRateByCurrency(ChargeId, CurrencyID, Rate)
select c.ChargeId, e.ExchangeId, 0.08
from dbo.OAS_ChargeInfo c with (nolock)
	cross join Custdb.dbo.Exchange e with(nolock) 
	left join dbo.LA_ChargeRateByCurrency s with (nolock) on c.ChargeId = s.ChargeId
where c.ProductId = 100
	and c.FromParty in (1, 9, 11, 98, 962, 25, 30)
	and c.ToParty = @PartyId
	and s.ChargeId is null
	AND e.Code = 'MYR'

	
-- insert System Mapping (SystemId = 2: OA)
insert into dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
select c.ChargeId, 2 as SystemId
from dbo.OAS_ChargeInfo c with (nolock)
	left join dbo.LA_ChargeInfo_SystemMapping s with (nolock) on c.ChargeId = s.ChargeId and s.SystemId = 2
where c.ProductId = 100
	and c.FromParty in (1, 9, 11, 98, 962, 25, 30)
	and c.ToParty = @PartyId
	and s.ChargeId is null



-- Insert Credit ChargeRate
DECLARE @HasInsertSetting BIT = 0;
IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK)
							   WHERE FromParty IN (25,30) 
									  AND ToParty = 1
									  AND ProductID = 100)
BEGIN
	-- Insert setting rate for Credit
	INSERT INTO OAS_ChargeInfo([ProductID]
								,[FromParty]
								,[ToParty]
								,[ParentChargeID]
								,[Rate]
								,[ChargeType]
								,[FromDate]
								,[ToDate]
								,[MinAmount]
								,[MaxAmount]
								,[Remark]
								,[BaseCurrencyId]
								,[FirstOfBilling]
								,[BasisOfBilling])
	VALUES(100, 25, 1, 0, 0, 1, '2024-11-19', '2050-01-01', null, null, null, null, null, null),
		  (100, 30, 1, 0, 0, 1, '2024-11-19', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty IN (25,30) 
		  AND ToParty = 1
		  AND ProductID = 100 
END
