/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[LA_LaunchSabaPlayLicensee]
	@NonOfficialPartyId		INT,
	@OperatorID				INT,
	@PayerName				VARCHAR(50),
	@BrandName				VARCHAR(100)	= '',
	@LicenseeCode			VARCHAR(50)		= '',
	@BaseCurrencyId			TINYINT,
	@LaunchDate				DATE, 
	@ProductIds				VARCHAR(MAX)	= '',
	@InvoiceLanguage		VARCHAR(7)		= '',
	@UserId					INT,
	@LoginIP				VARCHAR (50)	= '',
	@NewPartyId				INT				= 0		OUTPUT,
	@ErrCode				INT				= 0		OUTPUT,
	@ErrMsg					VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20250320@Danny
	Task : Launch new sabaplay licensee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20250320@Danny: Launch new saba play licensee
	
	Param's Explannation: 
	@ProductIds: [{"ProductID":1, "Productname":"abc"}]
		
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
	DECLARE @Products TABLE (ProductId INT, ProductName NVARCHAR(200))
	DECLARE @BillerId INT, @FirstDateOfMonth DATE

	-- Log
	DECLARE @logPayerSettingOld NVARCHAR(MAX), @logPayerSetting NVARCHAR(MAX), @logPayerSettingActionID INT
	DECLARE @logBillerOld NVARCHAR(MAX), @logBiller NVARCHAR(MAX), @logBllerActionID INT

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

		IF EXISTS (SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK) WHERE OldRefID = @OperatorID AND PartyType = 1 AND PlatformId = 2) 
		BEGIN
			SELECT @ErrMsg = 'Party has already been launched.', @ErrCode =  507
			RETURN
		END
	END

	INSERT INTO @Products (ProductId, ProductName)
	SELECT *
	FROM OPENJSON(@ProductIds)
	WITH (
		ProductId INT '$.ProductId',
		ProductName NVARCHAR(200) '$.ProductName'
	);

	SELECT @FirstDateOfMonth = DATEADD(MONTH, DATEDIFF(MONTH, 0, @LaunchDate), 0)

	SELECT @BillerId = PartyId
	FROM dbo.LA_BillerInfo WITH(NOLOCK)
	WHERE BillerName = 'SabaPlay'

	-- Launch licensee
	BEGIN TRY
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
						,lfs.PlatformName	AS 'pi.pp'
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
				INNER JOIN dbo.LA_f_PayerPlatform_Sel() lfs ON lfs.PlatformId = op2.PlatformId
				WHERE od.PartyID = @NonOfficialPartyId FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
			)
			

			UPDATE dbo.OAS_Party WITH(ROWLOCK)
			SET OldRefID   = @OperatorID
				,SetupName = PartyName
				,PartyType = 1
				,PartyName = @PayerName
			WHERE PartyID = @NonOfficialPartyId

			SET @NewPartyId = @NonOfficialPartyId
			SELECT @IsAddNew = 0, @logPayerSettingActionID = 1001

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

		-- OAS_PartyBaseCurrency
		IF EXISTS (SELECT 1 FROM dbo.OAS_PartyBaseCurrency WITH(NOLOCK) WHERE PartyID = @NewPartyId)
			DELETE dbo.OAS_PartyBaseCurrency WITH(ROWLOCK) WHERE PartyID = @NewPartyId
			
		INSERT INTO dbo.OAS_PartyBaseCurrency (PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)
		VALUES (@NewPartyId, @BaseCurrencyId, ISNULL(@LicenseeCode, ''), @FirstDateOfMonth, '2050-01-01')

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
							,STRING_AGG(p.ProductName,', ') ProductIDs
							,lt.InvTypeId
							,li.ToPartyId FakeID
					FROM LA_InvoiceSetting li WITH(NOLOCK) 
					LEFT JOIN LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
					LEFT JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
					LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
					LEFT JOIN @Products p ON li.ProductId = p.Productid
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
				SELECT InvTemplateId, InvTemplateName, 
				CASE WHEN InvTemplateName = '' THEN '' ELSE '' END InvTypeId
				FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
				WHERE InvTemplateName LIKE '%SabaPlay%'
			) ivt
				OUTER APPLY (
					SELECT p.ProductId
					FROM @Products p
					WHERE ivt.InvTemplateName IN ('SabaPlay')
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
							,STRING_AGG(p.ProductName,', ') ProductIDs
							,lt.InvTypeId
							,li.ToPartyId FakeID
					FROM LA_InvoiceSetting li WITH(NOLOCK) 
					LEFT JOIN LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
					LEFT JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
					LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
					LEFT JOIN @Products p ON li.ProductId = p.Productid
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
		WHERE u.[Name] = 'SabaPlay'

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
						,lfs.PlatformName	AS 'pi.pp'
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
				INNER JOIN dbo.LA_f_PayerPlatform_Sel() lfs ON lfs.PlatformId = op2.PlatformId
				WHERE od.PartyID = @NewPartyId FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
			)

	END TRY
	BEGIN CATCH
		-- Rollback
	
		UPDATE dbo.OAS_Party
		SET OldRefID   = NULL
			,SetupName = NULL
			,PartyType = 5
			,PartyName = ISNULL(SetupName, PartyName)
		WHERE PartyId = @NonOfficialPartyId

		UPDATE dbo.OAS_PartyDetail
		SET StatusId = 0
		WHERE PartyId = @NonOfficialPartyId
		
		DELETE dbo.OAS_PartyBaseCurrency WITH(ROWLOCK, UPDLOCK) WHERE PartyId = @NewPartyId
		DELETE dbo.LA_InvoiceSetting WITH(ROWLOCK, UPDLOCK) WHERE FromPartyId = @NewPartyId
		DELETE dbo.LA_UserParty WITH(ROWLOCK, UPDLOCK) WHERE PartyId = @NewPartyId
		DELETE dbo.LA_FunctionParty WITH(ROWLOCK, UPDLOCK) WHERE PartyId = @NewPartyId

		SELECT @ErrMsg = 'Launch licensee failed. Please try again.', @ErrCode =  503
		RETURN
	END CATCH

	-- Write log
	SET @EndRun = GETDATE()
	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, @EndRun)

	-- Write Log Payer Setting
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@SPName		= 'LA_LaunchSabaPlayLicensee'
		,@CustId		= @NewPartyId
		,@Duration		= @duration
		,@TrackingValue2 = @logPayerSetting
		,@TrackingValue = @logPayerSettingOld
		,@ActionID		 = @logPayerSettingActionID


	IF ISNULL(@BillerId, 0) <> 0
	BEGIN
		-- Write Biller Setting
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_LaunchSabaPlayLicensee'
			,@CustId		= @NewPartyId
			,@Duration		= @duration
			,@TrackingValue2 = @logBiller
			,@TrackingValue = @logBillerOld
			,@ActionID		 = 1002
	END
	
END
GO