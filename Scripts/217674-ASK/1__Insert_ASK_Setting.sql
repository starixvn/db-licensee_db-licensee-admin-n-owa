/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250218@Danny
	DB: DBCUST.bodb_licensee
	Description: Add setting rate ASK Terms:
*/

USE bodb_licensee
GO

-- insert new 3rd Party (Type = 3)
if not exists (select 1 from dbo.OAS_Party with (nolock) where PartyName = 'ASK' and PartyType = 3)
	insert into dbo.OAS_Party (PartyName, Description, PartyType)
	values ('ASK', 'ASK', 3)

declare @PartyId int
select @PartyId = PartyId from dbo.OAS_Party with (nolock) where PartyName = 'ASK' and PartyType = 3

BEGIN
-- Delete old setting
DECLARE @del_row TABLE(ChargeID INT)
DELETE FROM OAS_ChargeInfo WITH(ROWLOCK, UPDLOCK) 
OUTPUT deleted.ChargeID INTO @del_row
WHERE ToParty = @PartyId

DELETE FROM dbo.LA_ChargeRateByCurrency WITH(ROWLOCK, UPDLOCK)  WHERE ChargeID IN (SELECT d.ChargeID FROM @del_row d)

-- insert 3rd Rate (PaytoSupplier)
insert into dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
select t.ProductId, t.FromParty, t.ToParty, t.ParentChargeId, t.Rate, t.ChargeType, t.FromDate, t.ToDate
from (
	select 103 as ProductId, p.PartyId as FromParty, @PartyId as ToParty, 0 as ParentChargeId, 0.03 Rate, 1 as ChargeType, '2025-02-01' as FromDate, '2050-01-01' as ToDate 
	from (values (1), (9), (11), (98),(962), (1235), (25), (30)) as p (PartyId)
) t
	left join dbo.OAS_ChargeInfo c with (nolock) on t.ProductId = c.ProductId and t.FromParty = c.FromParty and t.ToParty = c.ToParty and t.FromDate <= c.ToDate and t.ToDate >= c.FromDate
where c.ProductId is null


-- insert 3rd Rate by Currency 
insert into dbo.LA_ChargeRateByCurrency(ChargeId, CurrencyID, Rate)
select c.ChargeId, e.ExchangeId, 0.04
from dbo.OAS_ChargeInfo c with (nolock)
	cross join Custdb.dbo.Exchange e with(nolock) 
	left join dbo.LA_ChargeRateByCurrency s with (nolock) on c.ChargeId = s.ChargeId
where c.ProductId = 103
	and c.FromParty in (1, 9, 11, 98, 962, 1235, 25, 30)
	and c.ToParty = @PartyId
	and s.ChargeId is null
	AND e.Code = 'THB'

	
-- insert System Mapping (SystemId = 2: OA)
insert into dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
select c.ChargeId, 2 as SystemId
from dbo.OAS_ChargeInfo c with (nolock)
	left join dbo.LA_ChargeInfo_SystemMapping s with (nolock) on c.ChargeId = s.ChargeId and s.SystemId = 2
where c.ProductId = 103
	and c.FromParty in (1, 9, 11, 98, 962, 1235, 25, 30)
	and c.ToParty = @PartyId
	and s.ChargeId is null


END
-- Insert Credit ChargeRate
DECLARE @HasInsertSetting BIT = 0;
IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK)
							   WHERE FromParty IN (25,30) 
									  AND ToParty = 1
									  AND ProductID = 103)
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
	VALUES(103, 25, 1, 0, 0, 1, '2025-02-01', '2050-01-01', null, null, null, null, null, null),
		  (103, 30, 1, 0, 0, 1, '2025-02-01', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty IN (25,30) 
		  AND ToParty = 1
		  AND ProductID = 103 
END
