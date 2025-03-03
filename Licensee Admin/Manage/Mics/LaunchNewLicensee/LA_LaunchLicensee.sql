/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_LaunchLicensee]
	@NonOfficialPartyId		INT,
	@LicenseeId				INT,
	@PayerName				VARCHAR(50),
	@BrandName				VARCHAR(100)	= '',
	@LicenseeCode			VARCHAR(50)		= '',
	@BaseCurrencyId			TINYINT,
	@LaunchDate				DATE, 
	@BillingGroupId			INT,
	@ProductIds				VARCHAR(1000)	= '',
	@InvoiceLanguage		VARCHAR(7)		= '',
	@ChargeInfoSettingData	NVARCHAR(MAX),
	@MinFeeSettingData		NVARCHAR(MAX)	= '',
	@UserId					INT,
	@LoginIP				VARCHAR (50)	= '',
	@NewPartyId				INT				= 0		OUTPUT,
	@ErrCode				INT				= 0		OUTPUT,
	@ErrMsg					VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20190107@Parsons
	Task : Launch new licensee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20190107@Parsons: Launch new licensee
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20190829@Bruce: Adding Licensee Code [#111586] 
		- 20210324@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
		- 20210811@Danny: Adding @InvoiceLanguage [#FeatureID 158133]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20220623@Percy: Remove dropdown function & user [RedmineID: #166504]
		- 20220831@Malcolm: Automate the PT adjustment when the charge rate is changed [RemineID: #171705]
		- 20221205@Danny: Remove Hx9candy From Crypto Licensee List [RedmineID: #181279]
		- 20230213@Malcolm: Fix duplicate data error [RemineID: #183774]
		- 20230310@Danny: Insert new log with more information [#FeatureID 175125]
		- 20230614@Danny: Enhance launch licensee function [#188014]
		- 20230815@Danny: Handle crypto licensee billing with fiat currency [RedmineID: #192378]
		- 20231002@Danny: logging currency information with new format [#FeatureID 193214]
		- 20231228@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
		- 20240520@Danny: support closed status invoice [RedmineID: #194603]
		- 20240527@Danny: Automate the PT adjustment when the Exchange charge rate is changed [RemineID: #201477]
		- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
		- 20250219@Danny: Integrate Double S System Inc group Licensees [RedmineID: #217961]
		- 20250303@Danny: Integrate Double S System Inc group Licensees [RedmineID: #217961]

	Param's Explannation: 
						@ChargeInfoSettingData = '<Root>
								<ChargeInfoSetting>
									<ProductId>0</ProductId>
									<Rate>0.15</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>15% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
									<ChargeTypeName>Licensing Fee</ChargeTypeName>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
								</ChargeInfoSetting>
								<ChargeInfoSetting>
									<ProductId>1</ProductId>
									<Rate>0.1</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>10% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
									<ChargeTypeName>Licensing Fee</ChargeTypeName>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
								</ChargeInfoSetting>
							</Root>'

							@MinFeeSettingData = '<Root>
								<MinFeeSetting>
									<ProductId>0</ProductId>
									<FeeTypeId>1</FeeTypeId>
									<FeeAmount>5000</FeeAmount>
									<BaseCurrencyID>6</BaseCurrencyID>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
									<MinFeeTerm>EUR 5,000 (Waived for the first 3 months after launched)</MinFeeTerm>
									<Priority>1</Priority>
								</MinFeeSetting>
								<MinFeeSetting>
									<ProductId>0</ProductId>
									<FeeTypeId>2</FeeTypeId>
									<FeeAmount></FeeAmount>
									<BaseCurrencyID>6</BaseCurrencyID>
									<FromDate>20190108</FromDate>
									<ToDate>20190407</ToDate>
									<MinFeeTerm></MinFeeTerm>
									<Priority>2</Priority>
								</MinFeeSetting>
							</Root>'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE 
		@StartRun		DATETIME = CURRENT_TIMESTAMP, 
		@EndRun			DATETIME, 
		@Duration		INT, 
		@Doing			NVARCHAR(MAX),
		@IsAddNew		BIT = 0

	SELECT @ErrCode = 0, @ErrMsg = ''

	-- Prepare input params
	DECLARE @Products TABLE (ProductId INT)
	DECLARE @ChargeInfoSettings	TABLE (ProductId INT, Rate MONEY, Remark NVARCHAR(400), BasisOfBilling NVARCHAR(500), ChargeType INT, ChargeTypeName NVARCHAR(100), FromDate DATE, ToDate DATE)
	DECLARE @MinFeeSettings	TABLE (ProductId TINYINT, FeeTypeId TINYINT, FeeAmount MONEY, FromDate DATE, ToDate DATE, MinFeeTerm NVARCHAR(1000), [Priority] TINYINT, MonthOfDeduction TINYINT)
	DECLARE @ChargeInfo TABLE (ChargeId INT, ProductId INT, ProductName VARCHAR(50), Rate MONEY, ChargeType INT, FromDate DATE, ToDate DATE, CurrencyId INT, SystemId INT, IsValid BIT DEFAULT(1),  ChargeTypeName NVARCHAR(100))
	DECLARE @AMF MONEY, @BillingGroupName NVARCHAR(50), @BillerId INT, @FirstDateOfMonth DATE

	-- Log
	DECLARE @logPayerSettingOld NVARCHAR(MAX), @logPayerSetting NVARCHAR(MAX), @logPayerSettingActionID INT
	DECLARE @logWaiveSettingOld NVARCHAR(MAX), @logWaiveSetting NVARCHAR(MAX), @logWaiveSettingActionID INT
	DECLARE @logMinFeeSettingOld NVARCHAR(MAX), @logMinFeeSetting NVARCHAR(MAX), @logMinFeeSettingActionID INT
	DECLARE @logBillerOld NVARCHAR(MAX), @logBiller NVARCHAR(MAX), @logBllerActionID INT
	DECLARE @logChargeRateOld NVARCHAR(MAX), @logChargeRate NVARCHAR(MAX), @logChargeRateActionID INT
	
	-- Charge Rate, Min Fee
	BEGIN TRY
		DECLARE @ChargeInfoSettingXML XML = CONVERT(XML, @ChargeInfoSettingData)
		DECLARE @MinFeeSettingXML XML = CONVERT(XML, @MinFeeSettingData)
		
		INSERT INTO @ChargeInfoSettings (ProductId, Rate, Remark, BasisOfBilling, ChargeType, ChargeTypeName, FromDate, ToDate)
		SELECT
			t.c.value('(ProductId/text())[1]', 'INT')					AS ProductId
			,t.c.value('(Rate/text())[1]', 'MONEY')						AS Rate
			,t.c.value('(Remark/text())[1]', 'NVARCHAR(400)')			AS Remark
			,t.c.value('(BasisOfBilling/text())[1]', 'NVARCHAR(500)')	AS BasisOfBilling
			,t.c.value('(ChargeType/text())[1]', 'INT')					AS ChargeType
			,t.c.value('(ChargeTypeName/text())[1]', 'NVARCHAR(100)')	AS ChargeTypeName
			,t.c.value('(FromDate/text())[1]', 'DATE')					AS FromDate
			,t.c.value('(ToDate/text())[1]', 'DATE')					AS ToDate
		FROM @ChargeInfoSettingXML.nodes('Root/ChargeInfoSetting') t(c)
		OPTION (OPTIMIZE FOR (@ChargeInfoSettingXML = NULL))

		INSERT INTO @MinFeeSettings (ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority])
		SELECT
			t.c.value('(ProductId/text())[1]', 'INT')					AS ProductId
			,t.c.value('(FeeTypeId/text())[1]', 'TINYINT')				AS FeeTypeId
			,t.c.value('(FeeAmount/text())[1]', 'MONEY')				AS FeeAmount
			,t.c.value('(FromDate/text())[1]', 'DATE')					AS FromDate
			,t.c.value('(ToDate/text())[1]', 'DATE')					AS ToDate
			,t.c.value('(MinFeeTerm/text())[1]', 'NVARCHAR(1000)')		AS MinFeeTerm
			,t.c.value('(Priority/text())[1]', 'TINYINT')				AS [Priority]
		FROM @MinFeeSettingXML.nodes('Root/MinFeeSetting') t(c)
		OPTION (OPTIMIZE FOR (@MinFeeSettingXML = NULL))
	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'Charge info/Min fee setting data invalid. Please try again.', @ErrCode =  501
		RETURN
	END CATCH

	-- Validate input params
	BEGIN
		IF @NonOfficialPartyId > 0 AND NOT EXISTS (SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyID = @NonOfficialPartyId) 
		BEGIN
			SELECT @ErrMsg = 'Party not found. Please try again.', @ErrCode =  505
			RETURN
		END

		IF EXISTS (SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyID <> @NonOfficialPartyId AND PartyName = @PayerName) 
		BEGIN
			SELECT @ErrMsg = 'Party name has already been existed. Please try again.', @ErrCode =  506
			RETURN
		END

		IF EXISTS (SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK) WHERE OldRefID = @LicenseeId AND PartyType = 1) 
		BEGIN
			SELECT @ErrMsg = 'Party has already been launched.', @ErrCode =  507
			RETURN
		END
	END

	INSERT INTO @Products (ProductId)
	SELECT value FROM STRING_SPLIT(@ProductIds, ',')

	SELECT @FirstDateOfMonth = DATEADD(MONTH, DATEDIFF(MONTH, 0, @LaunchDate), 0)

	SELECT @BillingGroupName = PartyName
	FROM dbo.OAS_Party WITH(NOLOCK)
	WHERE PartyId = @BillingGroupId

	SELECT @BillerId = PartyId
	FROM dbo.LA_BillerInfo WITH(NOLOCK)
	WHERE BillerName = CASE @BillingGroupName
						WHEN 'Boping' THEN @BillingGroupName
						WHEN 'JollySports' THEN @BillingGroupName
						WHEN 'Zelianta' THEN @BillingGroupName + ' Limited'
						WHEN 'Double S' THEN @BillingGroupName
						ELSE '' END

	SELECT @AMF = SUM(ISNULL(d.Income, 0))
	FROM dbo.LA_InvoiceHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceStatement d WITH(NOLOCK) ON h.InvoiceHeaderId = d.InvoiceHeaderId
	WHERE h.InvoiceType = 7 AND d.InvItemTypeId = 3 -- AMF in Setup fee
		AND h.StatusId <> -1 AND h.Environment = 'LOCAL'					
		AND h.PartyId = @NonOfficialPartyId
		AND h.CurrencyId = @BaseCurrencyId

	-- Launch licensee
	BEGIN TRY
		-- LicenseeProduct3rd
		UPDATE dbo.LicenseeProduct3rd WITH(ROWLOCK)
		SET EffectiveDate = @LaunchDate
		WHERE LicenseeId = @LicenseeId

		-- OAS_Party
		IF @NonOfficialPartyId > 0
		BEGIN
			SELECT @logPayerSettingOld = (
				SELECT	 Op2.PartyName							AS 'pi.pn'
						,x.GroupName							AS 'pi.bg' 
						,od.BrandName							AS 'pi.bn'
						,od.Description							AS 'pi.dc'
						,od.InvoiceLanguage						AS 'pi.iv'
						,FORMAT (od.LaunchDate,'MMM dd, yyyy') 	AS 'pi.ld'
					    ,FORMAT (od.SuspendedDate,'MMM dd, yyyy')	AS 'pi.sd'
					    ,FORMAT (od.TerminatedDate,'MMM dd, yyyy') AS 'pi.tmd'

						,od.CompanyName		AS 'a1.cn1'
						,od.AttnName		AS 'a1.an1'
						,od.Address1		AS 'a1.ad1'
						,od.CompanyName2	AS 'a2.cn2'
						,od.AttnName2		AS 'a2.an2'
						,od.Address2		AS 'a2.ad2'
						,ci.baseCurrInfo    AS 'bcs'
				FROM OAS_PartyDetail od WITH(NOLOCK)
				INNER JOIN OAS_Party op2 WITH(NOLOCK)  ON od.PartyID = op2.PartyID
				OUTER APPLY (SELECT TOP 1 oc.ToParty , pg.GroupName
							 FROM OAS_ChargeInfo oc WITH(NOLOCK) 
							 INNER JOIN dbo.LA_f_BillingGroupSel() pg ON pg.PartyId = oc.ToParty
							 WHERE od.PartyID = oc.FromParty AND oc.ChargeType = 1 
						 ) x
				OUTER APPLY (
								SELECT
								(
								SELECT CASE WHEN op.BaseCurrencyId = 142 THEN 'USDT' ELSE e.Code END  'c', 
										op.LicenseeCode 'lc', 
										op.FromDate 'fd', 
										op.ToDate  'td',
										CONVERT(VARCHAR(10),op.PartyID) +CONVERT(VARCHAR(10), op.BaseCurrencyId) + Convert(CHAR(8),op.FromDate,112) AS FakeID
								FROM OAS_PartyBaseCurrency op WITH(NOLOCK) 
								INNER JOIN CustDB.dbo.exchange e WITh(NOLOCK) ON op.BaseCurrencyId = e.ExchangeId
								WHERE op.PartyID = od.PartyID FOR JSON PATH , INCLUDE_NULL_VALUES    
								) AS  baseCurrInfo
							) ci
				WHERE od.PartyID = @NonOfficialPartyId FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
			)
			

			UPDATE dbo.OAS_Party WITH(ROWLOCK)
			SET OldRefID   = @LicenseeId
				,SetupName = PartyName
				,PartyType = 1
				,PartyName = @PayerName
			WHERE PartyID = @NonOfficialPartyId

			SET @NewPartyId = @NonOfficialPartyId
			SELECT @IsAddNew = 0, @logPayerSettingActionID = 1001

		END
		ELSE
		BEGIN
			INSERT INTO dbo.OAS_Party (PartyName, PartyType, OldRefID)
			VALUES (@PayerName, 1, @LicenseeId)

			SET @NewPartyId = SCOPE_IDENTITY()
			SELECT @IsAddNew = 1, @logPayerSettingActionID = 1000
		END

		-- OAS_PartyDetail
		IF EXISTS (SELECT 1 FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE PartyID = @NewPartyId)
			UPDATE dbo.OAS_PartyDetail WITH(ROWLOCK)
			SET BrandName = @BrandName
				,BaseCurrencyId = @BaseCurrencyId
				,StatusId = 1
				,LicenseeCode = @LicenseeCode
				,InvoiceLanguage = @InvoiceLanguage
				,LaunchDate = @LaunchDate
			WHERE PartyID = @NewPartyId
		ELSE
			INSERT INTO dbo.OAS_PartyDetail (PartyID, IsDeposit, BrandName, CompanyName, IsAllowedMemberComm, BaseCurrencyId, StatusId, LicenseeCode, InvoiceLanguage, LaunchDate)
			SELECT @NewPartyId, IsDeposit, @BrandName, CompanyName, IsAllowedMemberComm, @BaseCurrencyId, 1, @LicenseeCode, @InvoiceLanguage, @LaunchDate
			FROM dbo.Licensees WITH(NOLOCK)
			WHERE LicenseeID = @LicenseeId

		-- OAS_PartyBaseCurrency
		IF EXISTS (SELECT 1 FROM dbo.OAS_PartyBaseCurrency WITH(NOLOCK) WHERE PartyID = @NewPartyId)
			DELETE dbo.OAS_PartyBaseCurrency WITH(ROWLOCK) WHERE PartyID = @NewPartyId
			
		INSERT INTO dbo.OAS_PartyBaseCurrency (PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)
		VALUES (@NewPartyId, @BaseCurrencyId, ISNULL(@LicenseeCode, ''), @FirstDateOfMonth, '2050-01-01')

		-- OAS_ChargeInfo
		INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, Remark, BasisOfBilling, ChargeType, FirstOfBilling, FromDate, ToDate, BaseCurrencyId)
		OUTPUT INSERTED.ChargeID, INSERTED.ProductID, inserted.Rate, inserted.ChargeType, inserted.FromDate, inserted.ToDate, 2, 0 
			INTO @ChargeInfo (ChargeID, ProductId, Rate, ChargeType, FromDate, ToDate, SystemId, CurrencyId)
		SELECT ProductId, @NewPartyId, @BillingGroupId, 0, Rate, Remark, BasisOfBilling, ChargeType, FromDate, FromDate, ToDate, @BaseCurrencyId
		FROM @ChargeInfoSettings

		IF @BillingGroupId = 1 -- OW
			INSERT INTO @ChargeInfo (ChargeId, ProductId, SystemId)
			SELECT ChargeId, ProductId, 4
			FROM @ChargeInfo
			WHERE ProductId IN (0, 2, 3, 4, 5, 10, 11, 12) -- SB,NG,BA,LC,VS,AGC,GD,VG

		UPDATE c
		SET c.ChargeTypeName = cs.ChargeTypeName
		FROM	@ChargeInfo c
		INNER JOIN @ChargeInfoSettings cs ON c.ProductId = cs.ProductId AND c.ChargeType = cs.ChargeType AND c.FromDate = cs.FromDate
		
		-- LA_ChargeInfo_SystemMapping
		INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
		SELECT ChargeId, SystemID FROM @ChargeInfo

		IF ISNULL(@AMF, 0) > 0
			UPDATE @MinFeeSettings
			SET MonthOfDeduction = CEILING(@AMF / NULLIF(FeeAmount, 0))
			WHERE FeeTypeId = 1 AND ProductId = 0
		
		-- LA_MinFee
		INSERT INTO dbo.LA_MinFee (PartyId, ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority], CurrencyId, MonthOfDeduction)
		SELECT @NewPartyId, ProductId, FeeTypeId, FeeAmount, FromDate, CASE WHEN FeeTypeId = 2 THEN EOMONTH(ToDate) ELSE ToDate END, MinFeeTerm, [Priority], @BaseCurrencyId, MonthOfDeduction 
		FROM @MinFeeSettings

		-- LA_InvoiceSetting
		IF ISNULL(@BillerId, 0) <> 0
		BEGIN
			; WITH items AS
				(
				SELECT  op.PartyName,od.BrandName,iv.BillerName,iv.bank,iv.InvTypeName,iv.InvTemplateName,iv.ActiveAddress,iv.ProductIDs,iv.InvTypeId, iv.FakeID
				FROM	OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyID = op.PartyID
				OUTER APPLY (
					SELECT b.BillerName
							,lt.InvTypeName
							,temp.InvTemplateName
							,CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END Bank
								,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
									WHEN li.ActiveAddress = 2 THEN od.Address2 END ActiveAddress
							,STRING_AGG(CASE WHEN li.ProductID = 0 THEN 'Sportsbook' ELSE p.ProductName END,', ') ProductIDs
							,lt.InvTypeId
							,li.ToPartyId FakeID
					FROM LA_InvoiceSetting li WITH(NOLOCK) 
					LEFT JOIN LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
					LEFT JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
					LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
					LEFT JOIN Product3rd p WITH (NOLOCK) ON li.ProductId = p.Productid
					WHERE li.FromPartyId = op.PartyID AND li.ToPartyId = @BillerID
					GROUP BY b.BillerName, lt.InvTypeName, CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END
						, temp.InvTemplateName ,li.ActiveAddress
						,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
							WHEN li.ActiveAddress = 2 THEN od.Address2 END, lt.InvTypeId
						,li.ToPartyId
				) iv
				WHERE op.PartyID =@NewPartyId 
			), i AS
			(
				SELECT i.PartyName, i.BrandName, i.BillerName, i.Bank, i.FakeID
				FROM items i
				GROUP BY i.PartyName, i.BrandName, i.BillerName, i.Bank, i.FakeID
			),log_detail AS
			(
			SELECT i.FakeID, i.PartyName, i.BrandName, i.BillerName, i.Bank 
					,i1.InvTypeName it1, i1.InvTemplateName itn1, i1.ActiveAddress ad1, i1.ProductIDs p1
					,i3.InvTypeName it3, i3.InvTemplateName itn3, i3.ActiveAddress ad3
					,i4.InvTypeName it4, i4.InvTemplateName itn4, i4.ActiveAddress ad4
					,i5.InvTypeName it5, i5.InvTemplateName itn5, i5.ActiveAddress ad5
					,i6.InvTypeName it6, i6.InvTemplateName itn6, i6.ActiveAddress ad6
					,i7.InvTypeName it7, i7.InvTemplateName itn7, i7.ActiveAddress ad7
					,i10.InvTypeName it10, i10.InvTemplateName itn10, i10.ActiveAddress ad10
					,i11.InvTypeName it11, i11.InvTemplateName itn11, i11.ActiveAddress ad11
					,i12.InvTypeName it12, i12.InvTemplateName itn12, i12.ActiveAddress ad12
					, ISNULL(i1.InvTypeId,0) + ISNULL(i3.InvTypeId,0) + ISNULL(i4.InvTypeId,0) + ISNULL(i5.InvTypeId,0) + ISNULL(i6 .InvTypeId,0) + ISNULL(i7.InvTypeId,0)
					+ ISNULL(i11.InvTypeId,0) + ISNULL(i12.InvTypeId,0) AS istotal

			FROM  i
			LEFT JOIN items i1 ON i1.PartyName = i.PartyName AND ISNULL(i1.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i1.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i1.Bank,'') = ISNULL(i.Bank,'') AND i1.InvTypeId = 1 
			LEFT JOIN items i3 ON i3.PartyName = i.PartyName AND ISNULL(i3.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i3.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i3.Bank,'') = ISNULL(i.Bank,'') AND i3.InvTypeId = 3 
			LEFT JOIN items i4 ON i4.PartyName = i.PartyName AND ISNULL(i4.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i4.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i4.Bank,'') = ISNULL(i.Bank,'') AND i4.InvTypeId = 4 
			LEFT JOIN items i5 ON i5.PartyName = i.PartyName AND ISNULL(i5.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i5.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i5.Bank,'') = ISNULL(i.Bank,'') AND i5.InvTypeId = 5 
			LEFT JOIN items i6 ON i6.PartyName = i.PartyName AND ISNULL(i6.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i6.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i6.Bank,'') = ISNULL(i.Bank,'') AND i6.InvTypeId = 6 
			LEFT JOIN items i7 ON i7.PartyName = i.PartyName AND ISNULL(i7.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i7.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i7.Bank,'') = ISNULL(i.Bank,'') AND i7.InvTypeId = 7
			LEFT JOIN items i10 ON i10.PartyName = i.PartyName AND ISNULL(i10.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i10.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i10.Bank,'') = ISNULL(i.Bank,'') AND i10.InvTypeId = 10 
			LEFT JOIN items i11 ON i11.PartyName = i.PartyName AND ISNULL(i11.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i11.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i11.Bank,'') = ISNULL(i.Bank,'') AND i11.InvTypeId = 11 
			LEFT JOIN items i12 ON i12.PartyName = i.PartyName AND ISNULL(i12.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i12.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i12.Bank,'') = ISNULL(i.Bank,'') AND i12.InvTypeId = 12 
			)SELECT @logBillerOld = 
			(
				SELECT  l.PartyName as 'pi.pn', l.BrandName AS 'pi.bn' , x.x AS 'bl'
				FROM log_detail l
				OUTER APPLY 
				(
					SELECT 
					( 
						SELECT u.FakeID ,u.BillerName AS bln, u.Bank AS b, 
							u.it1, u.itn1, u.ad1, u.p1
							,u.it3, u.itn3, u.ad3
							,u.it4, u.itn4, u.ad4
							,u.it5, u.itn5, u.ad5
							,u.it6, u.itn6, u.ad6
							,u.it7, u.itn7, u.ad7
							,u.it10, u.itn10, u.ad10
							,u.it11, u.itn11, u.ad11
							,u.it12, u.itn12, u.ad12
						FROM log_detail u 
						WHERE u.PartyName = l.PartyName AND ISNULL(u.BrandName,'') = ISNULL(l.BrandName,'') AND l.istotal > 0
						FOR JSON PATH
					)x
				) x
				GROUP BY l.PartyName, l.BrandName , x.x FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
			)

			INSERT INTO dbo.LA_InvoiceSetting (FromPartyId, ToPartyId, ProductId, InvTypeId, InvTempId, BankId, ActiveAddress)
			SELECT DISTINCT @NewPartyId, @BillerId, ProductId, InvTypeId, InvTemplateId, 0 AS BankId, 1 AS ActiveAddress
			FROM (
				SELECT InvTemplateId, InvTemplateName
						,CASE InvTemplateName
							WHEN @BillingGroupName THEN 1	-- Software Data & Licensing Fees
							WHEN 'Double-S' THEN 1
							WHEN 'Credit' + CASE WHEN @BillingGroupName = 'JollySports' THEN '-JollySports' ELSE '' END THEN 4 -- Credit Note
							WHEN 'Credit' + CASE WHEN @BillingGroupName = 'Double S' THEN '-Double-S' ELSE '' END THEN 4 -- Credit Note
							ELSE 5 -- Debit Note
							END AS InvTypeId
				FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
				WHERE 1 = CASE InvTemplateName
							WHEN @BillingGroupName THEN 1
							WHEN CASE WHEN @BillingGroupName = 'Double S' THEN 'Double-S' ELSE '' END THEN 1
							WHEN 'Credit'+ CASE WHEN @BillingGroupName = 'JollySports' THEN '-JollySports'
												WHEN @BillingGroupName = 'Double S' THEN '-Double-S' ELSE '' END THEN 1
							WHEN 'Debit' + CASE WHEN @BillingGroupName = 'Zelianta' THEN '-Zelianta' 
												WHEN @BillingGroupName = 'JollySports' THEN '-JollySports'
												WHEN @BillingGroupName = 'Double S' THEN '-Double-S'
												ELSE '' END THEN 1
							ELSE 0 END
			) ivt
				OUTER APPLY (
					SELECT p.ProductId
					FROM @Products p
						INNER JOIN dbo.OAS_ChargeInfo c WITH(NOLOCK) ON p.ProductId = c.ProductId
					WHERE c.FromParty = @NewPartyId AND c.ToParty = @BillingGroupId
						AND c.FromDate = @LaunchDate
						AND ivt.InvTemplateName IN ('Boping', 'Zelianta', 'JollySports','Double-S')
				) p


			--write biller log
			; WITH items AS
			(
				SELECT  op.PartyName,od.BrandName,iv.BillerName,iv.bank,iv.InvTypeName,iv.InvTemplateName,iv.ActiveAddress,iv.ProductIDs,iv.InvTypeId, iv.FakeID
				FROM	OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyID = op.PartyID
				OUTER APPLY (
					SELECT b.BillerName
							,lt.InvTypeName
							,temp.InvTemplateName
							,CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END Bank
								,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
									WHEN li.ActiveAddress = 2 THEN od.Address2 END ActiveAddress
							,STRING_AGG(CASE WHEN li.ProductID = 0 THEN 'Sportsbook' ELSE p.ProductName END,', ') ProductIDs
							,lt.InvTypeId
							,li.ToPartyId FakeID
					FROM LA_InvoiceSetting li WITH(NOLOCK) 
					LEFT JOIN LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
					LEFT JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
					LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
					LEFT JOIN Product3rd p WITH (NOLOCK) ON li.ProductId = p.Productid
					WHERE li.FromPartyId = op.PartyID AND li.ToPartyId = @BillerID
					GROUP BY b.BillerName, lt.InvTypeName, CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END
						, temp.InvTemplateName ,li.ActiveAddress
						,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
							WHEN li.ActiveAddress = 2 THEN od.Address2 END, lt.InvTypeId
						,li.ToPartyId
				) iv
				WHERE op.PartyID =@NewPartyId 
			), i AS
			(
				SELECT i.PartyName, i.BrandName, i.BillerName, i.Bank, i.FakeID
				FROM items i
				GROUP BY i.PartyName, i.BrandName, i.BillerName, i.Bank, i.FakeID
			),log_detail AS
			(
			SELECT i.FakeID, i.PartyName, i.BrandName, i.BillerName, i.Bank 
					,i1.InvTypeName it1, i1.InvTemplateName itn1, i1.ActiveAddress ad1, i1.ProductIDs p1
					,i3.InvTypeName it3, i3.InvTemplateName itn3, i3.ActiveAddress ad3
					,i4.InvTypeName it4, i4.InvTemplateName itn4, i4.ActiveAddress ad4
					,i5.InvTypeName it5, i5.InvTemplateName itn5, i5.ActiveAddress ad5
					,i6.InvTypeName it6, i6.InvTemplateName itn6, i6.ActiveAddress ad6
					,i7.InvTypeName it7, i7.InvTemplateName itn7, i7.ActiveAddress ad7
					,i10.InvTypeName it10, i10.InvTemplateName itn10, i10.ActiveAddress ad10
					,i11.InvTypeName it11, i11.InvTemplateName itn11, i11.ActiveAddress ad11
					,i12.InvTypeName it12, i12.InvTemplateName itn12, i12.ActiveAddress ad12
					, ISNULL(i1.InvTypeId,0) + ISNULL(i3.InvTypeId,0) + ISNULL(i4.InvTypeId,0) + ISNULL(i5.InvTypeId,0) + ISNULL(i6 .InvTypeId,0) + ISNULL(i7.InvTypeId,0)
					+ ISNULL(i11.InvTypeId,0) + ISNULL(i12.InvTypeId,0) AS istotal

			FROM  i
			LEFT JOIN items i1 ON i1.PartyName = i.PartyName AND ISNULL(i1.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i1.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i1.Bank,'') = ISNULL(i.Bank,'') AND i1.InvTypeId = 1 
			LEFT JOIN items i3 ON i3.PartyName = i.PartyName AND ISNULL(i3.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i3.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i3.Bank,'') = ISNULL(i.Bank,'') AND i3.InvTypeId = 3 
			LEFT JOIN items i4 ON i4.PartyName = i.PartyName AND ISNULL(i4.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i4.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i4.Bank,'') = ISNULL(i.Bank,'') AND i4.InvTypeId = 4 
			LEFT JOIN items i5 ON i5.PartyName = i.PartyName AND ISNULL(i5.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i5.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i5.Bank,'') = ISNULL(i.Bank,'') AND i5.InvTypeId = 5 
			LEFT JOIN items i6 ON i6.PartyName = i.PartyName AND ISNULL(i6.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i6.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i6.Bank,'') = ISNULL(i.Bank,'') AND i6.InvTypeId = 6 
			LEFT JOIN items i7 ON i7.PartyName = i.PartyName AND ISNULL(i7.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i7.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i7.Bank,'') = ISNULL(i.Bank,'') AND i7.InvTypeId = 7
			LEFT JOIN items i10 ON i10.PartyName = i.PartyName AND ISNULL(i10.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i10.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i10.Bank,'') = ISNULL(i.Bank,'') AND i10.InvTypeId = 10 
			LEFT JOIN items i11 ON i11.PartyName = i.PartyName AND ISNULL(i11.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i11.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i11.Bank,'') = ISNULL(i.Bank,'') AND i11.InvTypeId = 11 
			LEFT JOIN items i12 ON i12.PartyName = i.PartyName AND ISNULL(i12.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i12.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i12.Bank,'') = ISNULL(i.Bank,'') AND i12.InvTypeId = 12 
			)SELECT @logBiller = 
			(
				SELECT  l.PartyName as 'pi.pn', l.BrandName AS 'pi.bn' , x.x AS 'bl'
				FROM log_detail l
				OUTER APPLY 
				(
					SELECT 
					( 
						SELECT u.FakeID ,u.BillerName AS bln, u.Bank AS b, 
							u.it1, u.itn1, u.ad1, u.p1
							,u.it3, u.itn3, u.ad3
							,u.it4, u.itn4, u.ad4
							,u.it5, u.itn5, u.ad5
							,u.it6, u.itn6, u.ad6
							,u.it7, u.itn7, u.ad7
							,u.it10, u.itn10, u.ad10
							,u.it11, u.itn11, u.ad11
							,u.it12, u.itn12, u.ad12
						FROM log_detail u 
						WHERE u.PartyName = l.PartyName AND ISNULL(u.BrandName,'') = ISNULL(l.BrandName,'') AND l.istotal > 0
						FOR JSON PATH
					)x
				) x
				GROUP BY l.PartyName, l.BrandName , x.x FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
			)
		END

		-- LA_UserParty
		DECLARE @ExcludeUsers TABLE (UserName VARCHAR(50))
		DECLARE @ExcludeUsersJson VARCHAR(4000)
		
		SELECT @ExcludeUsersJson = a.[Value]
		FROM dbo.LA_SystemSettings s WITH (NOLOCK)
			CROSS APPLY (SELECT t.[Value] FROM OPENJSON(s.[Value]) t) a
		WHERE s.[Key] = 'LaunchLicensee_ExcludeUser'
		
		;WITH CTE_ExcludeUsers AS (
			SELECT [Name], Users
			FROM OPENJSON(@ExcludeUsersJson) WITH (
				[Name] VARCHAR(100) '$.Name',
				Users NVARCHAR(MAX) '$.Users' AS JSON
			)
		)
		INSERT INTO @ExcludeUsers (UserName)
		SELECT b.[Value]
		FROM CTE_ExcludeUsers u
			CROSS APPLY (
				SELECT a.[Value] FROM OPENJSON(u.Users) a
			) b
		WHERE u.[Name] = @BillingGroupName

		INSERT INTO dbo.LA_UserParty (UserID, PartyID, Modifydate, Modifier, StatusID)
		SELECT UserID, @NewPartyId, GETDATE(), @UserID, 1
		FROM dbo.LA_User u WITH (NOLOCK)
			LEFT JOIN @ExcludeUsers eu ON u.Username = eu.UserName
		WHERE StatusID = 1 -- Active users
			AND eu.UserName IS NULL

		-- LA_FunctionParty
		INSERT INTO dbo.LA_FunctionParty (FunctionID, PartyID)
		SELECT FunctionID, @NewPartyId
		FROM dbo.LA_Function WITH (NOLOCK) 
		WHERE StatusID = 1 -- Active functions

		SELECT @logPayerSetting = (
				SELECT	 Op2.PartyName							AS 'pi.pn'
						,x.GroupName							AS 'pi.bg' 
						,od.BrandName							AS 'pi.bn'
						,od.Description							AS 'pi.dc'
						,od.InvoiceLanguage						AS 'pi.iv'
						,FORMAT (od.LaunchDate,'MMM dd, yyyy') 	AS 'pi.ld'
					    ,FORMAT (od.SuspendedDate,'MMM dd, yyyy')	AS 'pi.sd'
					    ,FORMAT (od.TerminatedDate,'MMM dd, yyyy') AS 'pi.tmd'

						,od.CompanyName		AS 'a1.cn1'
						,od.AttnName		AS 'a1.an1'
						,od.Address1		AS 'a1.ad1'
						,od.CompanyName2	AS 'a2.cn2'
						,od.AttnName2		AS 'a2.an2'
						,od.Address2		AS 'a2.ad2'
						,ci.baseCurrInfo    AS 'bcs'
				FROM OAS_PartyDetail od WITH(NOLOCK)
				INNER JOIN OAS_Party op2 WITH(NOLOCK)  ON od.PartyID = op2.PartyID
				OUTER APPLY (
							 SELECT TOP 1 oc.ToParty , pg.GroupName
							 FROM OAS_ChargeInfo oc WITH(NOLOCK) 
							 INNER JOIN dbo.LA_f_BillingGroupSel() pg ON pg.PartyId = oc.ToParty
							 WHERE od.PartyID = oc.FromParty AND oc.ChargeType = 1 
							 ) x
				OUTER APPLY (
								SELECT
								(
								SELECT CASE WHEN op.BaseCurrencyId = 142 THEN 'USDT' ELSE e.Code END  'c', 
										op.LicenseeCode 'lc', 
										op.FromDate 'fd', 
										op.ToDate  'td',
										CONVERT(VARCHAR(10),op.PartyID) +CONVERT(VARCHAR(10), op.BaseCurrencyId) + Convert(CHAR(8),op.FromDate,112) AS FakeID
								FROM OAS_PartyBaseCurrency op WITH(NOLOCK) 
								INNER JOIN CustDB.dbo.exchange e WITh(NOLOCK) ON op.BaseCurrencyId = e.ExchangeId
								WHERE op.PartyID = od.PartyID FOR JSON PATH , INCLUDE_NULL_VALUES    
								) AS  baseCurrInfo
							) ci
				WHERE od.PartyID = @NewPartyId FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
			)

		-- Log chargeRate
		;WITH t AS
		(
			SELECT		op.PartyName,
						od.BrandName,
						CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END Product,
						FORMAT (oc.FromDate,'MMM dd, yyyy') FromDate,
					    FORMAT (oc.ToDate,'MMM dd, yyyy') ToDate,
					    FORMAT (oc.FirstOfBilling,'MMM dd, yyyy') FirstOfBilling,
						oc.BasisOfBilling,
						CASE WHEN oc.ProductID = 3 THEN '0.25 %' ELSE (CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %') END Rate,
						STRING_AGG(x.Code,', ') Currs,
						CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END isMasterRate,
						oc.ChargeID AS FakeID,
						z.ChargeTypeName
			FROM OAS_Party op WITH(NOLOCK)
			INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON op.PartyID = od.PartyID
			INNER JOIN Licensees l WITH(NOLOCK) ON op.OldRefID = l.LicenseeID
			INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON op.PartyID = oc.FromParty
			CROSS APPLY (
				SELECT DISTINCT lc.Currency, CASE WHEN e.ExchangeId = 142 THEN 'USDT' WHEN e.ExchangeId IN (96,202,206,208,209) THEN  e.Code + ' (' + e.currency + ')'  ELSE e.Code END Code
				FROM LicenseeCust lc  WITH(NOLOCK) 
				INNER JOIN  CustDB.dbo.exchange e with(nolock) on lc.Currency = e.ExchangeId
				WHERE lc.LicenseeID = l.LicenseeID and lc.roleID = 2 and e.ExchangeId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
			) x
			INNER JOIN @ChargeInfo z ON z.ChargeId = oc.ChargeID AND z.ChargeTypeName IS NOT NULL
			LEFT JOIN  LA_ChargeRateByCurrency lcr WITH(NOLOCK) ON oc.ChargeID = lcr.ChargeID AND x.Currency = lcr.CurrencyID
			LEFT JOIN  Product3rd p3 WITH(NOLOCK) ON oc.ProductID = p3.Productid
			WHERE op.PartyID = @NewPartyId
			GROUP BY op.PartyName,
						od.BrandName,
						CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END,
						FORMAT (oc.FromDate,'MMM dd, yyyy'),
					    FORMAT (oc.ToDate,'MMM dd, yyyy'),
					    FORMAT (oc.FirstOfBilling,'MMM dd, yyyy'),
						oc.BasisOfBilling,
						CASE WHEN oc.ProductID = 3 THEN '0.25 %' ELSE (CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %') END,
						CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END,
						oc.ChargeID,
						z.ChargeTypeName
		) 
		, t1 AS
		(
			SELECT t.FakeID, t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,t.ChargeTypeName,STRING_AGG(cr.r, CHAR(13)) AS r
			FROM t
			CROSS APPLY (
					SELECT CASE WHEN t.isMasterRate = 1 AND EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'Others ' 
								WHEN t.isMasterRate = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'All ' 
								ELSE '' END + '('+ t.Currs + ') - ' + Rate AS r
			) cr
			GROUP BY t.FakeID, t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,t.ChargeTypeName
		) SELECT @logChargeRate = 
			(
			SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn', crs.crs AS 'crs'
			FROM t1 t 
			CROSS APPLY 
			(
				SELECT 
				(
					SELECT  u.FakeID ,u.Product p ,  u.FromDate fd, u.ToDate td , u.FirstOfBilling fb, u.BasisOfBilling bb , u.r, u.ChargeTypeName t
					FROM t1 u  WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName FOR JSON PATH
				) crs
			) crs  
			GROUP BY t.PartyName, t.BrandName, crs.crs
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
		)

		IF EXISTS  (SELECT TOP 1 1 FROM @MinFeeSettings WHERE FeeTypeId = 2)
			SELECT @logWaiveSetting = (
				SELECT	op.PartyName AS 'pi.pn' ,
						od.BrandName AS 'pi.bn',
						lm.lm AS 's'
				FROM OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyId = op.PartyID
				CROSS APPLY (
					SElECT 
					(
						SELECT CASE WHEN lm.Productid = 0 THEN 'Sportbook' ELSE  p.ProductName END AS pdn, 
									FORMAT (lm.FromDate,'MMM dd, yyyy')  AS fd,
									FORMAT (lm.Todate,'MMM dd, yyyy') AS td,
									lm.MinFeeId AS FakeID
						FROM  LA_MinFee lm WITH(NOLOCK)
						LEFT JOIN Product3rd p with(nolock) ON lm.ProductId = p.Productid
						WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =2 
						FOR JSON PATH
					) AS lm
				) lm
				WHERE op.PartyId = @NewPartyId
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES)
		
		IF EXISTS  (SELECT TOP 1 1 FROM @MinFeeSettings WHERE FeeTypeId = 1)
		SELECT @logMinFeeSetting = (
			SELECT	op.PartyName AS 'pi.pn' ,
					od.BrandName AS 'pi.bn',
					lm.lm AS 's'
			FROM OAS_Party op WITH(NOLOCK)
			INNER JOIN OAS_PartyDetail od with(nolock) ON od.PartyId = op.PartyID
			CROSS APPLY (
				SElECT 
				(
					SELECT CASE WHEN lm.Productid = 0 THEN 'Sportbook' ELSE  p.ProductName END AS pdn, 
								FORMAT (lm.FromDate,'MMM dd, yyyy') AS fd,
								FORMAT (lm.Todate,'MMM dd, yyyy') AS td,
								FORMAT(lm.FeeAmount,'N','en-us') as fa,
								e.Code AS c,
								lm.MinFeeTerm AS mt,
								lm.MinFeeId AS FakeID
					FROM  LA_MinFee lm WITH(NOLOCK)
					LEFT JOIN Product3rd p with(nolock) ON lm.ProductId = p.Productid
					INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON lm.CurrencyId = e.ExchangeId
					WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =1  
					FOR JSON PATH
				) as lm
			) lm
			where op.PartyId = @NewPartyId  
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES 
		)
		
		
	END TRY
	BEGIN CATCH
		-- Rollback
		IF @NonOfficialPartyId > 0
		BEGIN
			UPDATE dbo.OAS_Party
			SET OldRefID   = NULL
				,SetupName = NULL
				,PartyType = 5
				,PartyName = ISNULL(SetupName, PartyName)
			WHERE PartyId = @NonOfficialPartyId

			UPDATE dbo.OAS_PartyDetail
			SET StatusId = 0
			WHERE PartyId = @NonOfficialPartyId
		END
		ELSE
		BEGIN
			DELETE dbo.OAS_Party WHERE PartyId = @NewPartyId
			DELETE dbo.OAS_PartyDetail WHERE PartyId = @NewPartyId
		END

		DELETE l
		FROM dbo.LA_ChargeInfo_SystemMapping l WITH(ROWLOCK, UPDLOCK)
			INNER JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON l.ChargeID = c.ChargeID
		WHERE c.FromParty = @NewPartyId

		DELETE dbo.OAS_PartyBaseCurrency WITH(ROWLOCK, UPDLOCK) WHERE PartyId = @NewPartyId
		DELETE dbo.OAS_ChargeInfo WITH(ROWLOCK, UPDLOCK) WHERE FromParty = @NewPartyId
		DELETE dbo.LA_MinFee WITH(ROWLOCK, UPDLOCK) WHERE PartyID = @NewPartyId
		DELETE dbo.LA_InvoiceSetting WITH(ROWLOCK, UPDLOCK) WHERE FromPartyId = @NewPartyId
		DELETE dbo.LA_UserParty WITH(ROWLOCK, UPDLOCK) WHERE PartyId = @NewPartyId
		DELETE dbo.LA_FunctionParty WITH(ROWLOCK, UPDLOCK) WHERE PartyId = @NewPartyId

		SELECT @ErrMsg = 'Launch licensee failed. Please try again.', @ErrCode =  503
		RETURN
	END CATCH

	--Update PT
	DECLARE @CurrentDate DATE = CONVERT(DATE, GETDATE()), @SiteName VARCHAR(20) ='', @InputPT VARCHAR(MAX) = '', @Username VARCHAR(50), @InputPTExchange VARCHAR(MAX) = '', 
		@ErrCodeExchange INT, @ErrMsgExchange	VARCHAR(4000)

	DELETE @ChargeInfo WHERE SystemId = 4

	SELECT @Username = Username FROM dbo.LA_User WITH(NOLOCK) WHERE UserID = @UserID 

	UPDATE @ChargeInfo
		SET IsValid = 0
	WHERE @CurrentDate NOT BETWEEN FromDate AND ToDate
	
	SELECT @SiteName = l.LicenseeName
	FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.Licensees l WITH(NOLOCK) ON p.OldRefID = l.LicenseeID
	WHERE l.IsDeposit = 1 AND p.PartyID = @NewPartyId

	DELETE cr
	FROM @ChargeInfo cr
	WHERE cr.ProductId IN (14, 17, 3, 10, 13, 16) OR  cr.ToDate < @CurrentDate OR @SiteName IN ('CandyA18','Crypto88') 
		OR EXISTS (
			SELECT 1 
			FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
			WHERE ci.ChargeID = cr.ChargeID AND cr.ProductId = 39 AND ci.ChargeType = 12
		)

	UPDATE c
		SET c.ProductId = CASE WHEN c.ProductId = 0 THEN 1 ELSE p.ProductId END, c.ProductName = CASE WHEN c.ProductId = 0 THEN 'Sportsbook' ELSE pr.ProductName END
	FROM @ChargeInfo c
		LEFT JOIN dbo.Product3rd pr WITH(NOLOCK) ON pr.Productid = c.ProductId
		LEFT JOIN DBPRO.bodb02.dbo.Products p WITH (NOLOCK) ON p.ProductPrefix = pr.ProductPrefix

	UPDATE c
		SET c.Rate = -1
	FROM @ChargeInfo c 
	WHERE c.ProductId = 1 AND (c.Rate > 0.12 AND @SiteName <> '9wickets')
	
	DELETE c
	FROM @ChargeInfo c
	WHERE NOT EXISTS (SELECT 1 FROM @ChargeInfo r WHERE r.ChargeID = c.ChargeID AND r.Rate <> -1)

	SELECT @InputPT = CONVERT(VARCHAR(MAX), 
	(
		SELECT 
			ProductId AS '@PID'
			,CurrencyId AS '@CID'
			,CASE WHEN Rate = -1 THEN -1 ELSE 100 * (1 - Rate) END AS '@PT' -- [-1] : not update
		FROM @ChargeInfo 
		WHERE IsValid = 1 AND ProductId <> 31
		FOR XML PATH ('PT'), ROOT('ROOT')
	))

	SELECT @InputPTExchange = CONVERT(VARCHAR(MAX), 
	(
		SELECT 
			ProductId AS '@PID'
			,CurrencyId AS '@CID'
			,CASE WHEN Rate = -1 THEN -1 ELSE 100 * (1 - Rate) END AS '@PT' -- [-1] : not update
		FROM @ChargeInfo 
		WHERE IsValid = 1 AND ProductId = 31
		FOR XML PATH ('PT'), ROOT('ROOT')
	))

	IF ISNULL(@SiteName, '') <> '' AND ( ISNULL(@InputPT, '') <> '' OR  ISNULL(@InputPTExchange, '') <> '' )
	BEGIN
		IF ISNULL(@InputPT, '') <> ''
			EXEC CustDB.dbo.Acc_Dep_LicenseeSetting_PTSettingUpd
				@Site = @SiteName
				,@InputPT = @InputPT
				,@UserID = @UserID
				,@Username = @Username
				,@IP = @LoginIP
				,@ErrCode = @ErrCode OUTPUT
				,@ErrMsg = @ErrMsg OUTPUT

		IF ISNULL(@InputPTExchange, '') <> ''
			EXEC CustDB.dbo.Acc_Dep_LicenseeSetting_ChargePTUpd
				@Site = @SiteName
				,@InputPT = @InputPTExchange
				,@UserID = @UserID
				,@Username = @Username
				,@IP = @LoginIP
				,@ErrCode = @ErrCodeExchange OUTPUT
				,@ErrMsg = @ErrMsgExchange OUTPUT

	END

	IF (@ErrCode  <> 0 OR @ErrCodeExchange <> 0  OR EXISTS (SELECT 1 FROM @ChargeInfo WHERE IsValid = 0)) AND ISNULL(@SiteName, '') <> '' 
	BEGIN
		IF @ErrCode <> 0 OR @ErrCodeExchange <> 0
		BEGIN
			IF @ErrCode <> 0
				SELECT 	@ErrMsg = STUFF((SELECT ',' + ProductName
				FROM @ChargeInfo 
				WHERE IsValid = 1 AND ProductId <> 31
				FOR XML PATH('')), 1, 1, '') + ': '+ @ErrMsg + '<br>'

			IF @ErrCodeExchange <> 0
				SELECT 	@ErrMsg = ISNULL(@ErrMsg, '') + STUFF((SELECT ',' + ProductName
				FROM @ChargeInfo 
				WHERE IsValid = 1 AND ProductId = 31
				FOR XML PATH('')), 1, 1, '') + ': '+ @ErrMsgExchange + '<br>'
		END

		SELECT @ErrMsg =  ISNULL(@ErrMsg, '') + ProductName + ': NAP PT update failed due to it''s not current charge rate' + '<br>'
		FROM @ChargeInfo
		WHERE IsValid = 0

		SET @ErrCode = 0
	END

	-- Write log
	SET @EndRun = GETDATE()
	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, @EndRun)

	-- Write Log Payer Setting
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@SPName		= 'LA_LaunchLicensee'
		,@CustId		= @NewPartyId
		,@Duration		= @duration
		,@TrackingValue2 = @logPayerSetting
		,@TrackingValue = @logPayerSettingOld
		,@ActionID		 = @logPayerSettingActionID

	--  Write Log ChargeRate Setting
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@SPName		= 'LA_LaunchLicensee'
		,@CustId		= @NewPartyId
		,@Duration		= @duration
		,@TrackingValue2 = @logChargeRate
		,@TrackingValue = @logChargeRateOld
		,@ActionID		 = 1200

	-- Write Log Waive Setting
	IF EXISTS  (SELECT TOP 1 1 FROM @MinFeeSettings WHERE FeeTypeId = 2)
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_LaunchLicensee'
			,@CustId		= @NewPartyId
			,@Duration		= @duration
			,@TrackingValue2 = @logWaiveSetting
			,@TrackingValue = @logWaiveSettingOld
			,@ActionID		 = 1400

	-- Write Min fee Setting
	IF EXISTS  (SELECT TOP 1 1 FROM @MinFeeSettings WHERE FeeTypeId = 1)
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_LaunchLicensee'
			,@CustId		= @NewPartyId
			,@Duration		= @duration
			,@TrackingValue2 = @logMinFeeSetting
			,@TrackingValue = @logMinFeeSettingOld
			,@ActionID		 = 1300
	
	IF ISNULL(@BillerId, 0) <> 0
	BEGIN
		-- Write Biller Setting
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_LaunchLicensee'
			,@CustId		= @NewPartyId
			,@Duration		= @duration
			,@TrackingValue2 = @logBiller
			,@TrackingValue = @logBillerOld
			,@ActionID		 = 1002
	END
	
END
GO