/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeBillingInfoSel]
	  @PartyId		INT
	, @ProductCode	VARCHAR(10)
	, @FromDate Date
	, @ToDate Date
AS
/*  Created: 20150318@Florent
	Task : Report - Licensee Settlement Report
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 201505628@Florent: implement code
		- 20150917@Victor: Support Chinese on Settings
		- 20151109@Victor: Support Billing information of all Charge Types [Redmine: #41032]
		- 20151230@Bravo: Add MGCRNG
		- 20161110@Bruce.bui: check first billing date
		- 20161130@Bruce.bui: 
			+ Update partyId from TINYINT to INT
			+ Re-structure SP
		- 20181220@Parsons: Integrate Bidme games  [#103695]
		- 20190404@Bruce: Return fistbliing date [#102830]
		- 20200418@Parsons: Indo 4D Integration [#130910]
		- 20200812@Happy: Get min fee terms with GMF higher priority [#134492]
		- 20211104@Parsons: GroupMinFee: Support prorated min fee and AMF deduction [#157652]
		- 20231225@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
		- 20240625@Danny: chaneg Minimum Fee Term description [RedmineID: #206117]

		
	Param's Explanation:

*/
BEGIN
	SET NOCOUNT ON

	DECLARE
		@FirstBilling DATE,
		@BasisOfBilling NVARCHAR(4000),
		@MinimumFees NVARCHAR(4000),
		@ProductId INT = (SELECT TOP 1 ProductId FROM dbo.LA_f_Products3rd(@ProductCode))

	DECLARE @ChargeInfo TABLE (
		ProductID		INT,
		FromParty		INT,
		ChargeType		TINYINT,
		FirstOfBilling	DATE,
		FromDate		DATE,
		BasisOfBilling	NVARCHAR(4000),
		ChargeID		INT,
		OriginalId		INT
	)

	IF(@ProductCode='MGCRNG' OR @ProductCode='MGCLC')
	BEGIN
		INSERT INTO @ChargeInfo
		SELECT ProductID,FromParty,ChargeType,FirstOfBilling,FromDate,BasisOfBilling,ChargeIdRef,ChargeId
		FROM dbo.OAS_ChargeInfoSub WITH (NOLOCK)
		WHERE FromParty = @PartyId AND ChargeType != 2
	END
	ELSE
	BEGIN
		INSERT INTO @ChargeInfo
		SELECT ProductID,FromParty,ChargeType,FirstOfBilling,FromDate,BasisOfBilling,ChargeID,ChargeId
		FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
		WHERE FromParty = @PartyId AND ChargeType != 2 AND ToParty IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z )
	END

	SELECT TOP 1
		@FirstBilling = ci.FirstOfBilling,
		@BasisOfBilling = ci.BasisOfBilling
	FROM @ChargeInfo ci
	INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeId = cs.ChargeID AND cs.SystemID = 2
	WHERE ci.FromParty = @PartyId AND ci.ProductID = @ProductId AND ChargeType != 12
	ORDER BY ci.FromDate DESC
	
	--Get fee term
	SELECT @MinimumFees = REPLACE(REPLACE(d.MinimumFeeTerm,'#Currency#',e.Code),'#MinimumFee#',FORMAT(d.MinimumFee,'###,###,###.##','en-us'))
	FROM dbo.LA_GroupMinFeeDetail d WITH(NOLOCK)
		INNER JOIN dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK) ON a.GroupMinFeeID = d.GroupMinFeeID
		INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON e.ExchangeID = d.CurrencyId
	WHERE @FromDate <= d.ToDate AND d.FromDate <= @ToDate
		AND a.PartyID = @PartyId
		AND d.ProductID = @ProductId

	IF ISNULL(@MinimumFees, '') = ''
	BEGIN
		SELECT TOP 1
			@MinimumFees = m.MinFeeTerm
		FROM dbo.LA_MinFee m WITH (NOLOCK)
		WHERE @FromDate <= m.ToDate AND m.FromDate <= @ToDate
			AND m.FeeTypeId = 1
			AND m.PartyId = @PartyId
			AND m.ProductId = @ProductId
	END
	
	SELECT ISNULL(@FirstBilling, CAST('19000101' AS DATE)) AS FirstBilling
		, ISNULL(@BasisOfBilling, '') AS BasisOfBilling
		, ISNULL(@MinimumFees, '') AS MinimumFees
END
GO