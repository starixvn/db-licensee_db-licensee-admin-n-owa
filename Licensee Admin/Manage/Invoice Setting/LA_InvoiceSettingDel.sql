/*<info serverAlias="DBCUST-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_InvoiceSettingDel] 
	@BillerID				INT				
	, @PayerID				INT					
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150414@Florent
	 Task : Biller Delete Payer setting
	 DB: DBCUST.bodb_Licensee
   
	 Revisions:
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20230310@Danny: Insert new log with more information [#FeatureID 175125]
		- 20250326@Eddie: Get view log with products of SabaPlay [RedmineID: #217740]
		- 20250512@Eddie: Enhance SP [RedmineID: #226204]

	 Params:
		+ @InvoiceSettingXML: '<InvoiceSettings>
									<InvoiceSetting>
										<InvoiceTypeId>1</InvoiceTypeId>  
										<InvoiceTemplateId>1</InvoiceTemplateId>
										<ProductIds ProductId = "1"></ProductIds>
										<ProductIds ProductId = "3"></ProductIds>
										<ProductIds ProductId = "5"></ProductIds>
									</InvoiceSetting>
							
									<InvoiceSetting>
										<InvoiceTypeId>2</InvoiceTypeId>  
										<InvoiceTemplateId>1</InvoiceTemplateId>
										<ProductIds />
									</InvoiceSetting>
							
									<InvoiceSetting>
										<InvoiceTypeId>3</InvoiceTypeId>  
										<InvoiceTemplateId>3</InvoiceTemplateId>
										<ProductIds />
									</InvoiceSetting>
								</InvoiceSettings>'	
*/
BEGIN
	SET NOCOUNT ON
	IF ISNULL(@PayerID, '') = '' OR ISNULL(@BillerID, '') = ''
		RETURN

	DECLARE @BillerNameAbbr NVARCHAR(10) = N'RHL', @IsDeleted BIT = 0

-- For writing log
	DECLARE 
		@startRun		DATETIME,
		@endRun			DATETIME,
		@duration		INT,
		@logSPData		NVARCHAR(MAX),
		@logSPDataOld	NVARCHAR(MAX)

	-- Time start
	SET @startRun = GETDATE()	
	
	IF EXISTS (SELECT 1 
					FROM dbo.LA_InvoiceSetting i WITH (NOLOCK) 						
					WHERE i.FromPartyId = @PayerID AND i.ToPartyId = @BillerID)	
	BEGIN		
		--write old log
		; WITH items AS
		(
			SELECT op.PartyName,od.BrandName,iv.BillerName,iv.bank,iv.InvTypeName,iv.InvTemplateName,iv.ActiveAddress,iv.ProductIDs,iv.InvTypeId, iv.FakeID
			FROM dbo.OAS_Party op WITH(NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail od WITH(NOLOCK) ON od.PartyID = op.PartyID
			OUTER APPLY (
				SELECT	li.ToPartyId AS FakeID
						,b.BillerName
						,lt.InvTypeName
						,temp.InvTemplateName
						,CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END Bank
							,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
								WHEN li.ActiveAddress = 2 THEN od.Address2 END ActiveAddress
						,STRING_AGG(CASE WHEN li.ProductID = 0 AND b.BillerNameAbbreviation <> @BillerNameAbbr THEN 'Sportsbook' 
										 WHEN ISNULL(li.ProductID, 0) <> 0 AND b.BillerNameAbbreviation <> @BillerNameAbbr THEN p.ProductName
									ELSE vw.ProductName END,', ') ProductIDs
						,lt.InvTypeId
				FROM dbo.LA_InvoiceSetting li WITH(NOLOCK) 
				LEFT JOIN dbo.LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
				LEFT JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
				LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
				LEFT JOIN dbo.Product3rd p WITH (NOLOCK) ON li.ProductId = p.Productid
				LEFT JOIN dbo.vw_SabaPlay_Products vw WITH (NOLOCK) ON vw.ProductId = li.Productid
				WHERE li.FromPartyId = op.PartyID
				GROUP BY b.BillerName, lt.InvTypeName, CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END
					, temp.InvTemplateName ,li.ActiveAddress
					,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
						WHEN li.ActiveAddress = 2 THEN od.Address2 END, lt.InvTypeId
					,li.ToPartyId
			) iv
			WHERE op.PartyID = @PayerID
		), i AS
		(
			SELECT i.PartyName, i.BrandName, i.BillerName, i.Bank ,i.FakeID
			FROM items i
			GROUP BY i.PartyName, i.BrandName, i.BillerName, i.Bank,i.FakeID
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
		)SELECT @logSPDataOld = 
		(
			SELECT l.PartyName as 'pi.pn', l.BrandName AS 'pi.bn' , x.x AS 'bl'
			FROM log_detail l
			OUTER APPLY 
			(
				SELECT 
				( 
					SELECT u.FakeID
						,u.BillerName AS bln, u.Bank AS b
						,u.it1, u.itn1, u.ad1, u.p1
						,u.it3, u.itn3, u.ad3
						,u.it4, u.itn4, u.ad4
						,u.it5, u.itn5, u.ad5
						,u.it6, u.itn6, u.ad6
						,u.it7, u.itn7, u.ad7
						,u.it10, u.itn10, u.ad10
						,u.it11, u.itn11, u.ad11
						,u.it12, u.itn12, u.ad12
					FROM log_detail u 
					WHERE u.PartyName = l.PartyName AND ISNULL(u.BrandName,'') = ISNULL(l.BrandName,'')  AND l.istotal > 0
					FOR JSON PATH
				)x
			) x
			GROUP BY l.PartyName, l.BrandName , x.x FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
		)

		--delete statement
		DELETE FROM dbo.LA_InvoiceSetting WITH (ROWLOCK, UPDLOCK)				
			WHERE FromPartyId = @PayerID 
				AND ToPartyId = @BillerId

		IF @@error <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 140	
			RETURN
		END

		-- Deleted flag
		SET @IsDeleted = 1

		--build new log
		; WITH items AS
		(
			SELECT op.PartyName,od.BrandName,iv.BillerName,iv.bank,iv.InvTypeName,iv.InvTemplateName,iv.ActiveAddress,iv.ProductIDs,iv.InvTypeId, iv.FakeID
			FROM dbo.OAS_Party op WITH(NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail od WITH(NOLOCK) ON od.PartyID = op.PartyID
			OUTER APPLY (
				SELECT b.BillerName
						,lt.InvTypeName
						,temp.InvTemplateName
						,CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END Bank
							,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
								WHEN li.ActiveAddress = 2 THEN od.Address2 END ActiveAddress
						,STRING_AGG(CASE WHEN li.ProductID = 0 AND b.BillerNameAbbreviation <> @BillerNameAbbr THEN 'Sportsbook' 
										 WHEN ISNULL(li.ProductID, 0) <> 0 AND b.BillerNameAbbreviation <> @BillerNameAbbr THEN p.ProductName
									ELSE vw.ProductName END,', ') ProductIDs
						,lt.InvTypeId
						,li.ToPartyId AS FakeID
				FROM dbo.LA_InvoiceSetting li WITH(NOLOCK) 
				LEFT JOIN dbo.LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
				LEFT JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
				LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
				LEFT JOIN dbo.Product3rd p WITH (NOLOCK) ON li.ProductId = p.Productid
				LEFT JOIN dbo.vw_SabaPlay_Products vw WITH (NOLOCK) ON vw.ProductId = li.Productid
				WHERE li.FromPartyId = op.PartyID
				GROUP BY b.BillerName, lt.InvTypeName, CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END
					, temp.InvTemplateName ,li.ActiveAddress
					,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
						WHEN li.ActiveAddress = 2 THEN od.Address2 END, lt.InvTypeId
					,li.ToPartyId
			) iv
			WHERE op.PartyID =@PayerID
		), i AS
		(
			SELECT i.PartyName, i.BrandName, i.BillerName, i.Bank, i.FakeID
			FROM items i
			GROUP BY i.PartyName, i.BrandName, i.BillerName, i.Bank, i.FakeID
		),log_detail AS
		(
		SELECT 
				i.FakeID,i.PartyName, i.BrandName, i.BillerName, i.Bank 
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
		)SELECT @logSPData = 
		(
			SELECT  l.PartyName as 'pi.pn', l.BrandName AS 'pi.bn' , x.x AS 'bl'
			FROM log_detail l
			OUTER APPLY 
			(
				SELECT 
				( 
					SELECT u.FakeID, u.BillerName AS bln, u.Bank AS b, 
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
					WHERE u.PartyName = l.PartyName AND ISNULL(u.BrandName,'') = ISNULL(l.BrandName,'')  AND l.istotal > 0
					FOR JSON PATH
				)x
			) x
			GROUP BY l.PartyName, l.BrandName , x.x FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
		)

		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	END

	IF @IsDeleted = 1
	BEGIN
		-- Write Log
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			 = @UserID
			,@IP			 = @LoginIP
			,@SPName		 = 'LA_InvoiceSettingDel'
			,@CustId		 = @PayerID
			,@Duration		 = @duration
			,@TrackingValue2 = @logSPData
			,@TrackingValue  =  @logSPDataOld
			,@ActionID		 = 1004
	END
END
GO