/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_LicenseeBillingInfoSel]
	  @PartyId		INT
	, @ProductCode	VARCHAR(10)
AS
/*  Created: 20150318@Florent
	Task : Report - Licensee Settlement Report
	Base on : IMS_LicenseeBillingInfoSel
	DB: DBLIC/bodb_Licensee

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
		WHERE FromParty = @PartyId AND ChargeType != 2
	END

	SELECT TOP 1
		@FirstBilling = ci.FirstOfBilling,
		@BasisOfBilling = ci.BasisOfBilling
	FROM @ChargeInfo ci
	INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeId = cs.ChargeID AND cs.SystemID = 2
	WHERE ci.FromParty = @PartyId AND ci.ProductID = @ProductId AND ChargeType != 12
	ORDER BY ci.FromDate DESC

	SELECT TOP 1
		@MinimumFees = m.MinFeeTerm
	FROM dbo.LA_MinFee m WITH (NOLOCK)
	WHERE CONVERT(DATE, GETDATE()) BETWEEN m.FromDate AND m.ToDate
		AND m.FeeTypeId = 1
		AND m.PartyId = @PartyId
		AND m.ProductId = @ProductId
	
	SELECT CASE
			WHEN @FirstBilling IS NULL OR CAST(@FirstBilling AS DATE) <= CAST('19000101' AS DATE) THEN ''
			ELSE CONVERT(VARCHAR(3),DATENAME(MONTH, DATEADD(MONTH, MONTH(@FirstBilling), - 1))) + '-' + SUBSTRING(CAST(YEAR(@FirstBilling) AS VARCHAR),3,2)
		END AS FirstBilling
		, ISNULL(@BasisOfBilling, '') AS BasisOfBilling
		, ISNULL(@MinimumFees, '') AS MinimumFees
END
GO