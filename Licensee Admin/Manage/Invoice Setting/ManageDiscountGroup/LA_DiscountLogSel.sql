/*<info serverAlias="DBLOG-bodb_CustomerLog" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_CustomerLog]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_DiscountLogSel](
	@FromDate	DATE,
	@ToDate		DATE,
	@GroupId	INT = 0,
	@ActionId	INT = 0
)
AS
/*
	Created: Bruce.Bui
	Date: 2018-06-28
	Task: Select discount log detail
	DB: DBLIC.bodb_licensee
	
	Revisions:
		- 20180628@Bruce: view log for discount [#94282]
*/

BEGIN
	SET NOCOUNT ON
	-- discount log actionid
	-- DiscountIns = 5516
	-- DiscountUpd = 5517
	-- DiscountDel = 5518

	SELECT l.LogId, l.LogDate, l.UserId, l.ActionId, l.TypeId, l.Doing AS [Data]
	FROM dbo.UserLog_UserControl l WITH(NOLOCK)
	WHERE (@GroupId=0 OR l.CustID = @GroupId)
		AND ((@ActionId=0 AND l.ActionID IN (5516,5517,5518)) OR l.ActionID = @ActionId)
		AND CAST(l.LogDate AS DATE) BETWEEN @FromDate AND @ToDate
	ORDER BY LogID DESC
END
GO