/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210205@Parsons
	Task: [Bobbet group] Change Todate from `31-01-2021` to `2020-12-31` [RedmineID: #150105]
	DB: DBCUST.bodb_licensee
	Description: [Bobbet group] Change Todate from `31-01-2021` to `2020-12-31` [RedmineID: #150105]
*/

USE bodb_licensee
GO

UPDATE LA_DiscountGroupHeader WITH(ROWLOCK)
SET ToDate = '2020-12-31',
	DiscountGroupName = DiscountGroupName + N'_Expired_2020_12_31'
WHERE DiscountGroupId = 211