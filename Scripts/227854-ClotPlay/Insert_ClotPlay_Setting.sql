/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250527@Corbin
	DB: DBCUST.bodb_licensee
	Description: Add setting rate CPRNG Terms:
*/

USE bodb_licensee
GO

-- insert new 3rd Party (Type = 3)
if not exists (select 1 from dbo.OAS_Party with (nolock) where PartyName = 'CPRNG' and PartyType = 3)
	insert into dbo.OAS_Party (PartyName, Description, PartyType)
	values ('CPRNG', 'CPRNG', 3)

declare @PartyId int
select @PartyId = PartyId from dbo.OAS_Party with (nolock) where PartyName = 'CPRNG' and PartyType = 3

DROP TABLE IF EXISTS #CurrencyTemp
CREATE TABLE #CurrencyTemp (
    Code NVARCHAR(10),
    CurrencyName NVARCHAR(10)
);

INSERT INTO #CurrencyTemp (Code, CurrencyName)
VALUES 
('HKD', 'HK$'),
('CNY', 'RMB'),
('PHP', 'PC'),
('IDR', 'IN'),
('USD', 'Yen'),
('IDR', 'IND'),
('IDR', 'IDD'),
('THB', 'THB'),
('KRW', 'Won'),
('IDR', 'DDD'),
('VND', 'INH'),
('USD', 'UT'),
('MMK', 'MMK');

BEGIN
-- Delete old setting
DECLARE @del_row TABLE(ChargeID INT)
DELETE FROM OAS_ChargeInfo WITH(ROWLOCK, UPDLOCK) 
OUTPUT deleted.ChargeID INTO @del_row
WHERE ToParty = @PartyId and ProductID = 109

DELETE FROM dbo.LA_ChargeRateByCurrency WITH(ROWLOCK, UPDLOCK)  WHERE ChargeID IN (SELECT d.ChargeID FROM @del_row d)
DELETE FROM dbo.LA_ChargeInfo_SystemMapping WITH(ROWLOCK, UPDLOCK)  WHERE ChargeID IN (SELECT d.ChargeID FROM @del_row d)

-- insert 3rd Rate (PaytoSupplier)
insert into dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
select t.ProductId, t.FromParty, t.ToParty, t.ParentChargeId, t.Rate, t.ChargeType, t.FromDate, t.ToDate
from (
	select 109 as ProductId, p.PartyId as FromParty, @PartyId as ToParty, 0 as ParentChargeId, 0.06 Rate, 1 as ChargeType, '2025-06-17' as FromDate, '2050-01-01' as ToDate 
	from (values (1), (9), (11), (98),(962), (1235), (25), (30)) as p (PartyId)
) t
	left join dbo.OAS_ChargeInfo c with (nolock) on t.ProductId = c.ProductId and t.FromParty = c.FromParty and t.ToParty = c.ToParty and t.FromDate <= c.ToDate and t.ToDate >= c.FromDate
where c.ProductId is null


-- insert 3rd Rate by Currency 
insert into dbo.LA_ChargeRateByCurrency(ChargeId, CurrencyID, Rate)
select c.ChargeId, e.ExchangeId, 0.05
from dbo.OAS_ChargeInfo c with (nolock)
	cross join Custdb.dbo.Exchange e with(nolock) 
	left join dbo.LA_ChargeRateByCurrency s with (nolock) on c.ChargeId = s.ChargeId
	inner join #CurrencyTemp t on e.Code = t.Code and e.currency = t.CurrencyName
where c.ProductId = 109
	and c.FromParty in (1, 9, 11, 98, 962, 1235, 25, 30)
	and c.ToParty = @PartyId
	and s.ChargeId is null

	
-- insert System Mapping (SystemId = 2: OA)
insert into dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
select c.ChargeId, 2 as SystemId
from dbo.OAS_ChargeInfo c with (nolock)
	left join dbo.LA_ChargeInfo_SystemMapping s with (nolock) on c.ChargeId = s.ChargeId and s.SystemId = 2
where c.ProductId = 109
	and c.FromParty in (1, 9, 11, 98, 962, 1235, 25, 30)
	and c.ToParty = @PartyId
	and s.ChargeId is null


END
-- Insert Credit ChargeRate
DECLARE @HasInsertSetting BIT = 0;
IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK)
							   WHERE FromParty IN (25,30) 
									  AND ToParty = 1
									  AND ProductID = 109)
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
	VALUES(109, 25, 1, 0, 0, 1, '2025-06-17', '2050-01-01', null, null, null, null, null, null),
		  (109, 30, 1, 0, 0, 1, '2025-06-17', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty IN (25,30) 
		  AND ToParty = 1
		  AND ProductID = 109 
END
